defmodule PauseAiCa.SourceIntake do
  @moduledoc "Restricted, replay-safe source observations. Never enrolls, sends or creates accounts."
  import Ecto.Query
  alias PauseAiCa.{Repo, ContactMigration}
  @sources ~w(historical-reconciliation global-registration global-monthly luma discord)
  defmodule Receipt do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    schema "crm_intake_receipts" do
      field :source, :string
      field :event_id, :string
      field :digest, :string
      field :import_id, :binary_id
      field :imported_count, :integer
      field :suppressed_count, :integer
      timestamps(type: :utc_datetime, updated_at: false)
    end
  end

  defmodule PendingSource do
    use Ecto.Schema
    @primary_key {:id, :binary_id, autogenerate: true}
    schema "crm_pending_sources" do
      field :source, :string
      field :external_key, :string
      field :digest, :string
      field :original, :map
      timestamps(type: :utc_datetime, updated_at: false)
    end
  end

  def ingest(source, event_id, rows) do
    if valid?(source, event_id, rows) do
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext('pauseai-contact-import'))")
        digest = hash(:erlang.term_to_binary(rows, [:deterministic]))

        case Repo.get_by(Receipt, source: source, event_id: event_id) do
          %Receipt{digest: ^digest} = receipt ->
            result(receipt, true)

          %Receipt{} ->
            Repo.rollback(:event_conflict)

          nil ->
            allowed =
              Enum.reject(
                rows,
                &suppressed?(
                  if(&1["email"] in [nil, ""], do: &1["source_key"], else: &1["email"])
                )
              )

            {address_rows, pending} = Enum.split_with(allowed, &(&1["email"] not in [nil, ""]))

            for row <- pending do
              Repo.insert!(
                %PendingSource{
                  source: source,
                  external_key: row["source_key"],
                  digest: hash(:erlang.term_to_binary(row, [:deterministic])),
                  original: row
                },
                on_conflict: :nothing,
                conflict_target: [:source, :external_key, :digest]
              )
            end

            import = ContactMigration.import_service(address_rows, source, event_id)

            receipt =
              Repo.insert!(%Receipt{
                source: source,
                event_id: event_id,
                digest: digest,
                import_id: import.import.id,
                imported_count: length(allowed),
                suppressed_count: length(rows) - length(allowed)
              })

            result(receipt, false)
        end
      end)
    else
      {:error, :invalid_payload}
    end
  end

  def pending_page(scope, page) do
    if PauseAiCa.Volunteers.superadmin?(scope) do
      latest =
        from p in PendingSource,
          distinct: [p.source, p.external_key],
          order_by: [asc: p.source, asc: p.external_key, desc: p.inserted_at, desc: p.id]

      query = from p in subquery(latest), order_by: [asc: p.source, asc: p.external_key]
      total = Repo.aggregate(query, :count)
      pages = max(1, Integer.ceil_div(total, 25))
      page = min(max(page, 1), pages)

      {:ok,
       %{
         entries: Repo.all(from p in query, limit: 25, offset: ^((page - 1) * 25)),
         total: total,
         page: page,
         pages: pages
       }}
    else
      {:error, :unauthorized}
    end
  end

  # Call alongside an authorized erasure. A tombstone prevents historical rediscovery.
  def suppress(email) do
    Repo.insert_all(
      "crm_intake_suppressions",
      [%{email_hash: email_hash(email), inserted_at: DateTime.utc_now(:second)}],
      on_conflict: :nothing
    )
  end

  defp suppressed?(email),
    do:
      Repo.exists?(from s in "crm_intake_suppressions", where: s.email_hash == ^email_hash(email))

  defp email_hash(email), do: email |> String.trim() |> String.downcase() |> hash()
  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp result(receipt, replayed),
    do: %{
      receipt_id: receipt.id,
      imported_count: receipt.imported_count,
      suppressed_count: receipt.suppressed_count,
      replayed: replayed
    }

  defp valid?(source, event_id, rows) do
    source in @sources and is_binary(event_id) and byte_size(event_id) in 1..200 and
      is_list(rows) and length(rows) in 1..25 and byte_size(Jason.encode!(rows)) <= 1_000_000 and
      Enum.all?(rows, fn
        %{"email" => email, "source_key" => key} = row when is_binary(email) and is_binary(key) ->
          byte_size(key) in 1..200 and byte_size(email) < 256 and
            (PhoenixCRM.Address.changeset(%PhoenixCRM.Address{}, email).valid? or
               (email == "" and source in ["discord", "historical-reconciliation"])) and
            is_binary(row["name"] || "") and is_binary(row["city"] || "") and
            row["status"] in [nil, "", "needs_review", "do_not_contact"] and
            not Enum.any?(~w(user_id role superadmin classification), &Map.has_key?(row, &1))

        _ ->
          false
      end)
  end
end
