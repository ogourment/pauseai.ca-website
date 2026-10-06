defmodule PauseAiCa.Newsletters.Batches do
  @moduledoc "Reviewed immutable message/audience snapshots and durable, actor-attributed delivery reservations."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers, Accounts, Newsletters, CRM, Mailer, MailSafety}
  alias PauseAiCa.Newsletters.{Batch, Delivery, Draft, Drafts, Subscription}
  @admin_limit 20
  @global_limit 100

  def quota(scope) do
    if Volunteers.superadmin?(scope) do
      cutoff = DateTime.add(DateTime.utc_now(), -3600)
      recent = from d in Delivery, where: d.attempted_at > ^cutoff
      global = Repo.aggregate(recent, :count)

      personal =
        Repo.aggregate(from(d in recent, where: d.authorizing_admin_id == ^scope.user.id), :count)

      oldest =
        Repo.one(from d in recent, order_by: d.attempted_at, limit: 1, select: d.attempted_at)

      if Volunteers.superadmin?(scope),
        do:
          {:ok,
           %{
             personal_remaining: max(0, @admin_limit - personal),
             global_remaining: max(0, @global_limit - global),
             next_slot: if(oldest, do: DateTime.add(oldest, 3600))
           }},
        else: {:error, :unauthorized}
    else
      {:error, :unauthorized}
    end
  end

  def list(scope, draft_id) do
    with {:ok, _} <- Drafts.get(scope, draft_id) do
      {:ok,
       Repo.all(
         from b in Batch,
           where: b.draft_id == ^draft_id and b.owner_id == ^scope.user.id,
           order_by: [desc: b.inserted_at, desc: b.id]
       )}
    end
  end

  def get(scope, id) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %Batch{} = batch <- Repo.get_by(Batch, id: uuid, owner_id: scope.user.id),
         true <- Volunteers.superadmin?(scope) do
      {:ok,
       %{
         batch: batch,
         deliveries: Repo.all(from d in Delivery, where: d.batch_id == ^uuid, order_by: d.email)
       }}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def audience(scope, "contacts", params) do
    with {:ok, page} <- CRM.directory_page(scope, params) do
      {:ok, origins} = CRM.directory_origins(scope, page.records)

      rows =
        Enum.map(page.records, fn record ->
          contact_target(record) |> Map.put(:origins, Map.get(origins, record.person.id, []))
        end)

      {:ok, Map.put(page, :rows, status_rows(rows, "contacts"))}
    end
  end

  def audience(scope, "newsletter", params) do
    with {:ok, page} <- Newsletters.audience_page(scope, params) do
      rows =
        Enum.map(page.rows, fn r ->
          %{
            id: r.subscription.id,
            name: "",
            email: r.subscription.email,
            status: if(r.status == :included, do: :available, else: :excluded)
          }
        end)

      {:ok, Map.put(page, :rows, rows)}
    end
  end

  def audience(_, _, _), do: {:error, :unauthorized}

  def prepare(scope, %Draft{} = expected, mode, keys, reviewed?) do
    authorized(scope, fn ->
      draft =
        case Drafts.get(scope, expected.id) do
          {:ok, draft} -> draft
          _ -> Repo.rollback(:unauthorized)
        end

      Repo.one!(from d in Draft, where: d.id == ^draft.id, lock: "FOR UPDATE")
      if draft.revision != expected.revision or draft.archived_at, do: Repo.rollback(:stale)

      if String.trim(draft.subject) == "" or String.trim(draft.source) == "",
        do: Repo.rollback(:content_required)

      if mode == "contacts" and reviewed? != true, do: Repo.rollback(:review_required)
      targets = targets!(scope, mode, keys)
      if Enum.any?(targets, &(&1.status != :available)), do: Repo.rollback(:ineligible)
      now = DateTime.utc_now()
      {sender_name, sender_email} = Application.fetch_env!(:pauseai_ca, :campaign_sender)

      preparation_key =
        :crypto.hash(
          :sha256,
          :erlang.term_to_binary(
            {draft.id, draft.revision, mode, digest(targets), sender_name, sender_email,
             MailSafety.environment()}
          )
        )

      case Repo.get_by(Batch, preparation_key: preparation_key) do
        %Batch{} = existing ->
          existing

        nil ->
          batch =
            Repo.insert!(%Batch{
              draft_id: draft.id,
              owner_id: scope.user.id,
              draft_revision: draft.revision,
              recipient_mode: mode,
              recipient_keys: Enum.map(targets, & &1.id),
              sender_name: sender_name,
              sender_email: sender_email,
              delivery_environment: to_string(MailSafety.environment()),
              subject: draft.subject,
              source: draft.source,
              preparation_key: preparation_key,
              audience_digest: digest(targets),
              reviewed_at: now
            })

          for target <- targets do
            token_result =
              if mode == "contacts",
                do: Newsletters.outreach_withdrawal_token(scope, target.email),
                else: Newsletters.issue_withdrawal_token(scope, target.id)

            raw =
              case token_result do
                {:ok, raw} -> raw
                {:error, reason} -> Repo.rollback(reason)
              end

            # Only encrypted capabilities are durable in the outbox; raw tokens never reach the browser.
            encrypted =
              Phoenix.Token.encrypt(PauseAiCaWeb.Endpoint, "newsletter delivery footer", raw)

            Repo.insert!(%Delivery{
              batch_id: batch.id,
              recipient_key: target.id,
              email: target.email,
              withdrawal_token: encrypted
            })
          end

          batch
      end
    end)
  end

  def approve(scope, id) do
    authorized(scope, fn ->
      batch = locked!(scope, id)
      if batch.state not in ["review", "paused"], do: Repo.rollback(:not_reviewable)

      if Repo.exists?(
           from d in Delivery,
             where: d.batch_id == ^batch.id and d.state in ["reserved", "unknown"]
         ),
         do: Repo.rollback(:reconciliation_required)

      if not current?(scope, batch), do: Repo.rollback(:stale)

      Repo.update!(
        Ecto.Changeset.change(batch,
          state: "approved",
          approver_id: scope.user.id,
          approved_at: DateTime.utc_now()
        )
      )
    end)
  end

  def pause(scope, id) do
    authorized(scope, fn ->
      batch = locked!(scope, id)

      Repo.update!(
        Ecto.Changeset.change(batch, state: "paused", approver_id: nil, approved_at: nil)
      )
    end)
  end

  @doc "Bounded explicit send/resume. Throttled rows stay pending; reservations are never automatically retried."
  def dispatch(scope, id), do: dispatch(scope, id, 0)

  @doc "Resumes approved queues under their persisted authorizing admin. No credentials or actor IDs come from a request."
  def dispatch_pending do
    batches =
      Repo.all(
        from b in Batch,
          where: b.state in ["approved", "sending"],
          order_by: [asc: b.approved_at, asc: b.id]
      )

    for batch <- batches do
      actor = Repo.get(Accounts.User, batch.approver_id)
      scope = if actor, do: Accounts.Scope.for_user(actor)

      if actor && Volunteers.superadmin?(scope) do
        dispatch(scope, batch.id)
      else
        Repo.update_all(
          from(b in Batch, where: b.id == ^batch.id and b.state in ["approved", "sending"]),
          set: [state: "paused", updated_at: DateTime.utc_now()]
        )
      end
    end
  end

  defp dispatch(_scope, _id, n) when n >= @admin_limit, do: {:ok, :throttled}

  defp dispatch(scope, id, n) do
    case reserve(scope, id) do
      {:ok, {:send, delivery}} ->
        case deliver(scope, delivery) do
          "accepted" ->
            dispatch(scope, id, n + 1)

          _ ->
            pause(scope, id)
            {:ok, :reconciliation_required}
        end

      {:ok, result} ->
        {:ok, result}

      error ->
        error
    end
  end

  defp reserve(scope, id) do
    authorized(scope, fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext('pauseai-newsletter-delivery-quota'))")
      batch = locked!(scope, id)

      cond do
        batch.state not in ["approved", "sending"] ->
          :not_approved

        batch.approver_id != scope.user.id ->
          Repo.rollback(:unauthorized)

        not current?(scope, batch) ->
          Repo.update!(
            Ecto.Changeset.change(batch, state: "stale", approver_id: nil, approved_at: nil)
          )

          :stale

        true ->
          reserve_pending(batch)
      end
    end)
  end

  defp reserve_pending(batch) do
    unresolved =
      Repo.all(
        from d in Delivery, where: d.batch_id == ^batch.id and d.state in ["reserved", "unknown"]
      )

    cutoff = DateTime.add(DateTime.utc_now(), -300)

    stale_reserved =
      Enum.filter(
        unresolved,
        &(&1.state == "reserved" and DateTime.compare(&1.attempted_at, cutoff) == :lt)
      )

    cond do
      Enum.any?(unresolved, &(&1.state == "unknown")) or stale_reserved != [] ->
        for d <- stale_reserved,
            do:
              Repo.update!(
                Ecto.Changeset.change(d,
                  state: "unknown",
                  error: "Interrupted submission; provider reconciliation required."
                )
              )

        Repo.update!(Ecto.Changeset.change(batch, state: "paused"))
        :reconciliation_required

      unresolved != [] ->
        :already_sending

      true ->
        reserve_available(batch)
    end
  end

  defp reserve_available(batch) do
    pending =
      Repo.one(
        from d in Delivery,
          where: d.batch_id == ^batch.id and d.state == "pending",
          order_by: d.email,
          limit: 1,
          lock: "FOR UPDATE"
      )

    if is_nil(pending) do
      # Unknown/reserved submissions need reconciliation, never a blind resend.
      unresolved? =
        Repo.exists?(
          from d in Delivery,
            where: d.batch_id == ^batch.id and d.state in ["reserved", "unknown"]
        )

      Repo.update!(
        Ecto.Changeset.change(batch, state: if(unresolved?, do: "paused", else: "completed"))
      )

      if unresolved?, do: :reconciliation_required, else: :completed
    else
      cutoff = DateTime.add(DateTime.utc_now(), -3600)
      attempts = from d in Delivery, where: d.attempted_at > ^cutoff
      total = Repo.aggregate(attempts, :count)

      actor =
        Repo.aggregate(
          from(d in attempts, where: d.authorizing_admin_id == ^batch.approver_id),
          :count
        )

      if total >= @global_limit or actor >= @admin_limit do
        :throttled
      else
        Repo.update!(Ecto.Changeset.change(batch, state: "sending"))

        {:send,
         Repo.update!(
           Ecto.Changeset.change(pending,
             state: "reserved",
             authorizing_admin_id: batch.approver_id,
             attempted_at: DateTime.utc_now()
           )
         )}
      end
    end
  end

  defp deliver(scope, delivery) do
    # The durable reservation was committed before provider I/O. A crash keeps it reserved,
    # requiring operator reconciliation instead of sending the same message twice.
    result =
      authorized(scope, fn ->
        batch = locked!(scope, delivery.batch_id)
        if batch.state != "sending" or not current?(scope, batch), do: Repo.rollback(:stale)

        case Phoenix.Token.decrypt(
               PauseAiCaWeb.Endpoint,
               "newsletter delivery footer",
               delivery.withdrawal_token,
               max_age: :infinity
             ) do
          {:ok, raw} ->
            link =
              PauseAiCaWeb.Site.url(
                "en",
                "/newsletters/withdraw?" <> URI.encode_query(%{"token" => raw})
              )

            message =
              message(batch, delivery.email, link)
              |> Swoosh.Email.header("X-PauseAI-Delivery-Id", delivery.id)

            Mailer.deliver(message, admin_actor_id: batch.approver_id)

          _ ->
            Repo.rollback(:invalid_footer)
        end
      end)

    {state, provider, error} =
      case result do
        {:ok, {:ok, metadata}} ->
          {"accepted", provider_id(metadata), nil}

        {:ok, {:error, reason}}
        when reason in [:staging_admin_required, :mail_environment_blocked] ->
          {"failed", nil, to_string(reason)}

        {:error, reason} when reason in [:stale, :unauthorized, :invalid_footer] ->
          {"excluded", nil, to_string(reason)}

        _ ->
          {"unknown", nil, "Provider acceptance is uncertain; reconcile before retrying."}
      end

    Repo.update!(
      Ecto.Changeset.change(delivery,
        state: state,
        accepted_at: if(state == "accepted", do: DateTime.utc_now()),
        provider_id: provider,
        error: error
      )
    )

    state
  end

  defp message(batch, email, link) do
    {html, text} =
      PauseAiCaWeb.Emails.Layout.render(
        batch.subject,
        "",
        [],
        {"Manage my subscription", "Gérer mon abonnement", link},
        body_html: PauseAiCa.Mail.Render.html(batch.source),
        body_text: batch.source,
        footer:
          {"You are receiving a reviewed PauseAI Canada update. Manage your subscription using the link above.",
           "Vous recevez une communication révisée de PauseIA Canada. Gérez votre abonnement avec le lien ci-dessus."}
      )

    Swoosh.Email.new()
    |> Swoosh.Email.to(email)
    |> Swoosh.Email.from({batch.sender_name, batch.sender_email})
    |> Swoosh.Email.subject(batch.subject)
    |> Swoosh.Email.html_body(html)
    |> Swoosh.Email.text_body(text)
  end

  defp provider_id(metadata) when is_map(metadata),
    do: to_string(metadata[:id] || metadata["id"] || "")

  defp provider_id(_), do: ""

  defp current?(scope, batch) do
    case Drafts.get(scope, batch.draft_id) do
      {:ok, draft} when draft.revision == batch.draft_revision and is_nil(draft.archived_at) ->
        sender_current? =
          {batch.sender_name, batch.sender_email} ==
            Application.fetch_env!(:pauseai_ca, :campaign_sender) and
            batch.delivery_environment == to_string(MailSafety.environment())

        case targets(scope, batch.recipient_mode, batch.recipient_keys) do
          {:ok, rows} ->
            sender_current? and draft.subject == batch.subject and draft.source == batch.source and
              Enum.all?(rows, &(&1.status == :available)) and
              digest(rows) == batch.audience_digest

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp targets!(scope, mode, keys) do
    case targets(scope, mode, keys) do
      {:ok, rows} -> rows
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp targets(_scope, mode, keys) when mode in ["contacts", "newsletter"] and is_list(keys) do
    keys = Enum.uniq(keys)

    if length(keys) in 1..5000 and Enum.all?(keys, &match?({:ok, _}, Ecto.UUID.cast(&1))) do
      rows =
        if mode == "contacts" do
          people =
            Repo.all(from p in PhoenixCRM.Person, where: p.id in ^keys and is_nil(p.canonical_id))

          owners =
            Repo.all(from p in PhoenixCRM.Person, where: p.id in ^keys or p.canonical_id in ^keys)

          owner_ids = Enum.map(owners, & &1.id)
          addresses = Repo.all(from a in PhoenixCRM.Address, where: a.person_id in ^owner_ids)

          Enum.map(people, fn person ->
            ids = for p <- owners, p.id == person.id or p.canonical_id == person.id, do: p.id

            contact_target(%{
              person: person,
              addresses: Enum.filter(addresses, &(&1.person_id in ids))
            })
          end)
        else
          Repo.all(from s in Subscription, where: s.id in ^keys)
          |> Enum.map(&%{id: &1.id, name: "", email: &1.email, status: :available})
        end

      rows = rows |> status_rows(mode) |> Enum.sort_by(& &1.id)

      if length(rows) == length(keys) and length(Enum.uniq_by(rows, & &1.email)) == length(rows),
        do: {:ok, rows},
        else: {:error, :audience_changed}
    else
      {:error, :audience_required}
    end
  end

  defp targets(_, _, _), do: {:error, :audience_required}

  defp contact_target(record) do
    preferred = Enum.find(record.addresses, &(&1.id == record.person.preferred_address_id))

    address =
      preferred ||
        if(is_nil(record.person.preferred_address_id) and length(record.addresses) == 1,
          do: hd(record.addresses)
        )

    %{
      id: record.person.id,
      name: record.person.name || "",
      email: if(address, do: address.email),
      status: if(address, do: :available, else: :preferred_address_required)
    }
  end

  defp status_rows(rows, mode) do
    Enum.map(rows, fn row ->
      allowed? =
        if mode == "contacts",
          do: Newsletters.outreach_eligible?(row.email),
          else: Newsletters.eligible?(row.email)

      if row.status == :available and not allowed?, do: %{row | status: :excluded}, else: row
    end)
  end

  defp digest(rows),
    do:
      :crypto.hash(:sha256, :erlang.term_to_binary(Enum.map(rows, &{&1.id, &1.email, &1.status})))

  defp locked!(scope, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Batch{} = batch <-
           Repo.one(
             from b in Batch,
               where: b.id == ^uuid and b.owner_id == ^scope.user.id,
               lock: "FOR UPDATE"
           ) do
      batch
    else
      _ -> Repo.rollback(:unauthorized)
    end
  end

  defp authorized(scope, fun) do
    if Volunteers.superadmin?(scope) do
      Repo.transaction(fn ->
        Repo.one!(from u in Accounts.User, where: u.id == ^scope.user.id, lock: "FOR UPDATE")
        if not Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)
        fun.()
      end)
    else
      {:error, :unauthorized}
    end
  end
end
