defmodule PauseAiCa.Newsletters.Results do
  @moduledoc "Campaign reports and guarded provider-event reconciliation over frozen sends."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Newsletters.{Batch, Delivery, ResultSnapshot}

  def list(scope, page \\ 1) do
    if Volunteers.superadmin?(scope) do
      attempted = from d in Delivery, where: not is_nil(d.attempted_at), select: d.batch_id

      query =
        from b in Batch,
          where: b.id in subquery(attempted),
          order_by: [desc: b.inserted_at, desc: b.id]

      {:ok, Repo.all(from b in query, limit: 25, offset: ^((page - 1) * 25))}
    else
      {:error, :unauthorized}
    end
  end

  # Local receipts and persisted provider aggregates only: browsing never calls Brevo.
  def overview(scope, ids) do
    if Volunteers.superadmin?(scope) do
      states =
        Repo.all(
          from d in Delivery,
            where: d.batch_id in ^ids,
            group_by: [d.batch_id, d.state],
            select: {d.batch_id, d.state, count(d.id)}
        )
        |> Enum.group_by(&elem(&1, 0))

      snapshots =
        Repo.all(from s in ResultSnapshot, where: s.batch_id in ^ids)
        |> Map.new(&{&1.batch_id, &1})

      Map.new(ids, fn id ->
        {id,
         %{
           states: Map.new(Map.get(states, id, []), fn {_, state, count} -> {state, count} end),
           provider: Map.get(snapshots, id)
         }}
      end)
    else
      %{}
    end
  end

  # Retain the originating list order across detail patches, even when a newer send arrives.
  # IDs from URLs are bounded, UUID-checked and intersected with authorized attempted sends.
  def navigation(scope, id, ids) do
    if Volunteers.superadmin?(scope) do
      ids =
        Enum.take(ids, 25) |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1))) |> Enum.uniq()

      attempted = from d in Delivery, where: not is_nil(d.attempted_at), select: d.batch_id

      allowed =
        Repo.all(
          from b in Batch, where: b.id in ^ids and b.id in subquery(attempted), select: b.id
        )
        |> MapSet.new()

      ids = Enum.filter(ids, &MapSet.member?(allowed, &1))
      index = Enum.find_index(ids, &(&1 == id))

      %{
        ids: ids,
        previous: if(index && index > 0, do: Enum.at(ids, index - 1)),
        next: if(index, do: Enum.at(ids, index + 1))
      }
    else
      %{ids: [], previous: nil, next: nil}
    end
  end

  def list_context(scope, ids) do
    if Volunteers.superadmin?(scope) do
      navigation = navigation(scope, nil, ids)
      batches = Repo.all(from b in Batch, where: b.id in ^navigation.ids) |> Map.new(&{&1.id, &1})
      {:ok, Enum.map(navigation.ids, &Map.fetch!(batches, &1))}
    else
      {:error, :unauthorized}
    end
  end

  def recipient_counts(scope, ids) do
    if Volunteers.superadmin?(scope) do
      Repo.all(
        from d in Delivery,
          where: d.batch_id in ^ids,
          group_by: d.batch_id,
          select: {d.batch_id, count(d.id)}
      )
      |> Map.new()
    else
      %{}
    end
  end

  def recipient_summaries(scope, ids) do
    if Volunteers.superadmin?(scope) do
      Repo.all(
        from d in Delivery,
          where: d.batch_id in ^ids,
          group_by: d.batch_id,
          select:
            {d.batch_id,
             %{
               count: count(d.id),
               emails: fragment("(array_agg(? ORDER BY ?))[1:3]", d.email, d.email)
             }}
      )
      |> Map.new()
    else
      %{}
    end
  end

  defp provider_snapshot(batch, deliveries) do
    case Repo.get(ResultSnapshot, batch.id) do
      nil ->
        nil

      snapshot ->
        report = PhoenixMailWorkflow.Results.summarize(deliveries)

        observed =
          Map.new(report.observed, fn {key, _} ->
            {key, Map.get(snapshot.observed, Atom.to_string(key), 0)}
          end)

        %{
          report: %{report | observed: observed},
          links: saved_links(snapshot.observed),
          partial: snapshot.partial,
          refreshed_at: snapshot.refreshed_at
        }
    end
  end

  def get(scope, id) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, id} <- Ecto.UUID.cast(id),
         %Batch{} = batch <- Repo.get(Batch, id),
         deliveries when deliveries != [] <-
           Repo.all(from d in Delivery, where: d.batch_id == ^id, order_by: d.email),
         true <- Enum.any?(deliveries, &(not is_nil(&1.attempted_at))),
         true <- Volunteers.superadmin?(scope) do
      {:ok,
       %{
         batch: batch,
         deliveries: deliveries,
         report: PhoenixMailWorkflow.Results.summarize(deliveries),
         local_unsubscribed: local_unsubscribed(deliveries),
         current_withdrawn: current_withdrawn(deliveries),
         provider: provider_snapshot(batch, deliveries),
         reconciliation: PauseAiCa.Newsletters.ProviderReconciliation.summary(deliveries),
         deliverability_rows:
           PauseAiCa.Newsletters.ProviderReconciliation.review_rows(deliveries),
         synchronization: PauseAiCa.Newsletters.ProviderSync.status()
       }}
    else
      _ -> {:error, :unauthorized}
    end
  end

  # Delivery attribution survives a later pause clearing the batch approver.
  def senders(scope, batch_ids) do
    if Volunteers.superadmin?(scope) do
      rows =
        Repo.all(
          from d in Delivery,
            left_join: u in PauseAiCa.Accounts.User,
            on: u.id == d.authorizing_admin_id,
            where: d.batch_id in ^batch_ids and not is_nil(d.attempted_at),
            select: {d.batch_id, d.authorizing_admin_id, u.name, u.email},
            distinct: true
        )

      Enum.group_by(rows, &elem(&1, 0), fn {_, id, name, email} ->
        %{id: id, name: name, email: email}
      end)
    else
      %{}
    end
  end

  def contact_history(scope, person_id) do
    with {:ok, record} <- PauseAiCa.CRM.get(scope, person_id) do
      emails = Enum.map(record.addresses, & &1.email)

      rows =
        Repo.all(
          from d in Delivery,
            join: b in Batch,
            on: b.id == d.batch_id,
            left_join: u in PauseAiCa.Accounts.User,
            on: u.id == d.authorizing_admin_id,
            where: d.email in ^emails and not is_nil(d.attempted_at),
            order_by: [desc: d.attempted_at, desc: d.id],
            limit: 100,
            select: %{
              delivery: d,
              subject: b.subject,
              sender_name: b.sender_name,
              sender_email: b.sender_email,
              admin_name: u.name,
              admin_email: u.email
            }
        )

      other =
        Repo.all(
          from r in PauseAiCa.Mail.DeliveryReceipt,
            left_join: u in PauseAiCa.Accounts.User,
            on: u.id == r.actor_id,
            where: fragment("? && ?::text[]", r.recipients, ^emails),
            order_by: [desc: r.inserted_at, desc: r.id],
            limit: 100,
            select: %{receipt: r, admin_name: u.name, admin_email: u.email}
        )
        |> Enum.map(fn row ->
          %{
            delivery: %{
              batch_id: nil,
              email: Enum.find(row.receipt.recipients, &(&1 in emails)),
              state: row.receipt.state,
              attempted_at: row.receipt.inserted_at
            },
            subject: row.receipt.subject,
            sender_name: nil,
            sender_email: row.receipt.sender_email,
            admin_name: row.admin_name,
            admin_email: row.admin_email
          }
        end)

      {:ok,
       Enum.sort_by(rows ++ other, & &1.delivery.attempted_at, {:desc, DateTime})
       |> Enum.take(100)}
    end
  end

  def refresh(scope, id) do
    with {:ok, result} <- get(scope, id),
         true <- result.batch.delivery_environment == "production",
         key when is_binary(key) and key != "" <- Application.get_env(:pauseai_ca, :brevo_api_key) do
      first =
        result.deliveries
        |> Enum.map(& &1.attempted_at)
        |> Enum.reject(&is_nil/1)
        |> Enum.min(DateTime)

      from = DateTime.to_date(first)

      # The provider permits at most 90 days. Do not silently drop an older campaign's early outcomes.
      if Date.diff(Date.utc_today(), from) > 89 do
        {:error, :outside_retention_window}
      else
        with {:ok, page} <-
               PauseAiCa.Newsletters.ProviderHistory.report_pages(from, Date.utc_today()),
             :ok <- complete_report(page),
             {:ok, _} <- get(scope, id) do
          events = page.events
          partial = page.partial
          report = PhoenixMailWorkflow.Results.summarize(result.deliveries, events)
          links = link_report(result.batch.source, result.deliveries, events)
          at = DateTime.utc_now()
          # Persist only aggregate observations, never raw provider recipient events.
          Repo.transaction(fn ->
            if not Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)

            if PauseAiCa.Newsletters.ProviderSyncWorker.enabled?() do
              case PauseAiCa.Newsletters.ProviderReconciliation.reconcile(events) do
                {:ok, _} -> :ok
                {:error, reason} -> Repo.rollback(reason)
              end
            end

            Repo.insert!(
              %ResultSnapshot{
                batch_id: id,
                observed:
                  Map.new(report.observed, fn {k, v} -> {Atom.to_string(k), v} end)
                  |> Map.put("links", links),
                partial: partial,
                refreshed_at: at
              },
              on_conflict: {:replace, [:observed, :partial, :refreshed_at]},
              conflict_target: [:batch_id]
            )

            %{
              report: report,
              links: links,
              partial: partial,
              refreshed_at: at,
              reconciliation:
                PauseAiCa.Newsletters.ProviderReconciliation.summary(result.deliveries)
            }
          end)
        end
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_configured}
    end
  end

  # Only generic destinations present in immutable authored content are retained.
  # Raw provider rows, recipient identities and authentication/footer URLs stay out of this JSON.
  defp link_report(source, deliveries, events) do
    links =
      (source || "")
      |> MDEx.parse_document!()
      |> Enum.flat_map(fn
        %MDEx.Link{url: url, nodes: nodes} ->
          if safe_authored_url?(url),
            do: [%{"url" => url, "label" => String.slice(String.trim(link_text(nodes)), 0, 200)}],
            else: []

        _ ->
          []
      end)
      |> Enum.uniq_by(& &1["url"])

    allowed = MapSet.new(links, & &1["url"])

    recipients =
      deliveries
      |> Enum.filter(&(is_binary(&1.provider_id) and &1.provider_id != ""))
      |> MapSet.new(&{&1.provider_id, String.downcase(String.trim(&1.email))})

    clicks =
      Enum.reduce(events, %{}, fn
        %{"event" => type, "messageId" => id, "email" => email, "link" => url}, counts
        when type in ["clicked", "clicks"] and is_binary(id) and is_binary(email) and
               is_binary(url) ->
          pair = {id, String.downcase(String.trim(email))}

          if MapSet.member?(allowed, url) and MapSet.member?(recipients, pair) do
            Map.update(counts, url, MapSet.new([pair]), &MapSet.put(&1, pair))
          else
            counts
          end

        _, counts ->
          counts
      end)

    %{
      "version" => 1,
      "complete" => true,
      "items" =>
        Enum.map(links, fn link ->
          Map.put(link, "clicked", MapSet.size(Map.get(clicks, link["url"], MapSet.new())))
        end)
    }
  end

  defp link_text(nodes) do
    Enum.map_join(nodes, fn
      %{literal: text} when is_binary(text) -> text
      %{nodes: children} -> link_text(children)
      _ -> ""
    end)
  end

  defp saved_links(%{"links" => %{"version" => 1, "complete" => true, "items" => items} = links})
       when is_list(items), do: links

  defp saved_links(_), do: nil

  defp safe_authored_url?(url) do
    uri = URI.parse(url)
    decoded = url |> URI.decode() |> URI.decode() |> String.downcase()
    path = (uri.path || "") |> URI.decode() |> String.downcase()
    params = URI.query_decoder(uri.query || "") |> Enum.to_list()

    uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
      is_nil(uri.userinfo) and
      not String.contains?(decoded, ["@", "{{", "}}", "${", "[[", "]]", "<", ">"]) and
      not Regex.match?(
        ~r{(?:^|/)(?:unsubscribe|withdraw|confirm|confirm-email|log-in|login|sign-in|signin|auth|oauth|track|tracking)(?:/|$)},
        path
      ) and
      not Regex.match?(~r"(?:^|/)[a-z0-9_-]{64,}(?:/|$)", path) and
      not Enum.any?(params, fn {key, value} ->
        Regex.match?(
          ~r/token|secret|password|signature|auth|email|recipient|subscriber|contact_id|user_id|code|key/i,
          key
        ) or
          String.length(value) > 128 or String.contains?(URI.decode(value), ["@", "{{", "${"])
      end)
  rescue
    ArgumentError -> false
  end

  defp complete_report(%{partial: false}), do: :ok
  defp complete_report(_), do: {:error, :incomplete_history}

  defp current_withdrawn(deliveries) do
    emails = Enum.map(deliveries, & &1.email)

    Repo.aggregate(
      from(s in PauseAiCa.Newsletters.Subscription,
        where: s.email in ^emails and s.state == "withdrawn",
        distinct: s.email
      ),
      :count,
      :email
    )
  end

  defp local_unsubscribed(deliveries) do
    hashes =
      Enum.flat_map(deliveries, fn d ->
        case Phoenix.Token.decrypt(
               PauseAiCaWeb.Endpoint,
               "newsletter delivery footer",
               d.withdrawal_token || "",
               max_age: :infinity
             ) do
          {:ok, raw} -> [:crypto.hash(:sha256, raw)]
          _ -> []
        end
      end)

    ids =
      Repo.all(
        from t in PauseAiCa.Newsletters.WithdrawalToken,
          where: t.token_hash in ^hashes,
          select: t.id
      )

    delivery_ids = Enum.map(deliveries, & &1.id)

    Repo.aggregate(
      from(e in PauseAiCa.Newsletters.ConsentEvent,
        where:
          e.kind == "withdrawn" and
            (fragment("?->>'withdrawal_token_id'", e.evidence) in ^ids or
               fragment("?->>'newsletter_delivery_id'", e.evidence) in ^delivery_ids),
        distinct: e.subscription_id
      ),
      :count,
      :subscription_id
    )
  end
end
