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
        with {:ok, page} <- PauseAiCa.Newsletters.ProviderHistory.pages(from, Date.utc_today()),
             {:ok, _} <- get(scope, id) do
          events = page.events
          partial = page.partial
          report = PhoenixMailWorkflow.Results.summarize(result.deliveries, events)
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
                observed: Map.new(report.observed, fn {k, v} -> {Atom.to_string(k), v} end),
                partial: partial,
                refreshed_at: at
              },
              on_conflict: {:replace, [:observed, :partial, :refreshed_at]},
              conflict_target: [:batch_id]
            )

            %{
              report: report,
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
