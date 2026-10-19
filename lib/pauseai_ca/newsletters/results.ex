defmodule PauseAiCa.Newsletters.Results do
  @moduledoc "Read-only campaign reports over frozen sends and exact provider message observations."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Newsletters.{Batch, Delivery}

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
         local_unsubscribed: local_unsubscribed(deliveries)
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
        request =
          Req.new(
            base_url:
              Application.get_env(:pauseai_ca, :brevo_base_url, "https://api.brevo.com/v3"),
            headers: [{"api-key", key}],
            receive_timeout: 8_000,
            retry: false
          )
          |> Req.merge(Application.get_env(:pauseai_ca, :brevo_history_req_options, []))

        params = [
          startDate: Date.to_iso8601(from),
          endDate: Date.to_iso8601(Date.utc_today()),
          limit: 5000,
          sort: "asc"
        ]

        with {:ok, events, partial} <- events(request, params, 0, []),
             {:ok, _} <- get(scope, id) do
          {:ok,
           %{
             report: PhoenixMailWorkflow.Results.summarize(result.deliveries, events),
             partial: partial,
             refreshed_at: DateTime.utc_now(:second)
           }}
        end
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_configured}
    end
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

    Repo.aggregate(
      from(e in PauseAiCa.Newsletters.ConsentEvent,
        where:
          e.kind == "withdrawn" and fragment("?->>'withdrawal_token_id'", e.evidence) in ^ids,
        distinct: e.subscription_id
      ),
      :count,
      :subscription_id
    )
  end

  defp events(req, params, offset, acc) do
    case Req.get(req, url: "/smtp/statistics/events", params: params ++ [offset: offset]) do
      {:ok, %{status: 200, body: %{"events" => rows}}} when is_list(rows) ->
        all = acc ++ rows

        cond do
          length(rows) < 5000 -> {:ok, all, false}
          offset >= 15000 -> {:ok, all, true}
          true -> events(req, params, offset + 5000, all)
        end

      {:ok, %{status: 200, body: body}} when body == %{} ->
        {:ok, acc, false}

      {:ok, %{status: 429}} ->
        {:error, :rate_limited}

      _ ->
        {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end
end
