defmodule PauseAiCa.ContactMigration do
  import Ecto.Query

  alias PauseAiCa.Accounts.User
  alias PauseAiCa.ContactMigration.{Activity, Contact, Import}
  alias PauseAiCa.{Repo, CRM, Volunteers}
  alias PauseAiCa.Accounts.Scope

  def list_contacts(search \\ "") do
    list_contacts_page(search, 1, 100_000).entries
  end

  def list_contacts_page(search \\ "", page \\ 1, page_size \\ 25, receipt_id \\ nil) do
    pattern =
      "%" <>
        (search
         |> String.replace("\\", "\\\\")
         |> String.replace("%", "\\%")
         |> String.replace("_", "\\_")) <> "%"

    query =
      from(c in Contact,
        left_join: u in assoc(c, :user),
        where:
          ilike(c.email, ^pattern) or ilike(coalesce(c.name, ""), ^pattern) or
            ilike(coalesce(c.city, ""), ^pattern),
        preload: [user: u],
        order_by: [asc: c.email]
      )

    query =
      if is_nil(receipt_id) do
        query
      else
        observed =
          from a in Activity,
            where: fragment("?->>'import_id' = ?", a.details, ^receipt_id),
            select: a.contact_id

        from c in query, where: c.id in subquery(observed)
      end

    total = Repo.aggregate(exclude(query, :preload), :count, :id)
    pages = max(Integer.ceil_div(total, page_size), 1)
    page = page |> max(1) |> min(pages)

    entries = query |> limit(^page_size) |> offset(^((page - 1) * page_size)) |> Repo.all()
    %{entries: entries, page: page, page_size: page_size, pages: pages, total: total}
  end

  def list_activities(contact_id) do
    from(a in Activity,
      where: a.contact_id == ^contact_id,
      preload: [:actor_user],
      order_by: [desc: a.inserted_at]
    )
    |> Repo.all()
  end

  def receipts(scope) do
    if Volunteers.superadmin?(scope),
      do: Repo.all(from i in Import, order_by: [desc: i.inserted_at, desc: i.id], limit: 100),
      else: []
  end

  def receipt(scope, id) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, _} <- Ecto.UUID.cast(id),
         %Import{} = receipt <- Repo.get(Import, id),
         do: {:ok, receipt},
         else: (_ -> {:error, :unauthorized})
  end

  def contacts_page(scope, search, page, per, receipt_id) do
    with true <- Volunteers.superadmin?(scope),
         true <- is_nil(receipt_id) or match?({:ok, _}, receipt(scope, receipt_id)) do
      {:ok, list_contacts_page(search, page, per, receipt_id)}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def import_selected(rows, filename, source, actor) do
    Repo.transaction(fn ->
      # A single transaction serializes reconciliation and holds current roles through commit.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext('pauseai-contact-import'))")
      Repo.one(from u in User, where: u.id == ^actor.id, lock: "FOR UPDATE")
      scope = Scope.for_user(actor)
      if not Volunteers.superadmin?(scope), do: Repo.rollback({:actor, :unauthorized})

      receipt =
        %Import{}
        |> Import.changeset(%{
          filename: filename,
          source: source,
          selected_count: length(rows),
          imported_by_id: actor.id
        })
        |> Repo.insert!()

      contacts = Enum.map(rows, &upsert_contact(Repo, &1, source, receipt.id, actor.id))

      Enum.each(contacts, fn contact ->
        case CRM.link_contact(scope, contact) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback({:contacts, reason})
        end
      end)

      %{import: receipt, contacts: contacts}
    end)
    |> case do
      {:ok, result} -> {:ok, result}
      {:error, {step, reason}} -> {:error, step, reason, %{}}
    end
  end

  defp upsert_contact(repo, row, source, import_id, actor_id) do
    validation =
      Contact.changeset(%Contact{}, %{
        email: row["email"],
        source: source,
        classification: classification(row["status"])
      })

    if not validation.valid?, do: repo.rollback({:contacts, :invalid_row})
    email = row["email"] |> String.trim() |> String.downcase()
    user = repo.get_by(User, email: email)

    attrs = %{
      email: email,
      name: blank_to_nil(row["name"]),
      city: blank_to_nil(row["city"]),
      source: source,
      source_key: source_key(row),
      source_data: source_data(row),
      classification: classification(row["status"]),
      user_id: user && user.id,
      last_import_id: import_id
    }

    existing =
      source_contact(repo, source, attrs.source_key) || repo.get_by(Contact, email: email)

    existing =
      if existing,
        do: repo.one!(from c in Contact, where: c.id == ^existing.id, lock: "FOR UPDATE")

    if existing && existing.email != email,
      do: repo.rollback({:contacts, :source_identity_conflict})

    previous =
      existing &&
        %{
          "source" => existing.source,
          "source_key" => existing.source_key,
          "source_data" => existing.source_data,
          "import_id" => existing.last_import_id
        }

    attrs = preserve_human_fields(existing, attrs)
    contact = (existing || %Contact{}) |> Contact.changeset(attrs) |> repo.insert_or_update!()

    %Activity{}
    |> Activity.changeset(%{
      contact_id: contact.id,
      actor_user_id: actor_id,
      action: "imported",
      details: %{
        "account_match" => not is_nil(user),
        "import_id" => import_id,
        "source" => source,
        "source_key" => attrs.source_key,
        "source_data" => Map.drop(row, ~w(id valid)),
        "previous_observation" => previous
      }
    })
    |> repo.insert!()

    contact
  end

  defp source_contact(_repo, _source, nil), do: nil

  defp source_contact(repo, source, key) do
    ids =
      repo.all(
        from c in Contact, where: c.source == ^source and c.source_key == ^key, select: c.id
      )

    observed =
      repo.all(
        from a in Activity,
          where:
            fragment(
              "?->>'source' = ? AND ?->>'source_key' = ?",
              a.details,
              ^source,
              a.details,
              ^key
            ),
          select: a.contact_id,
          distinct: true
      )

    case Enum.uniq(ids ++ observed) do
      [] -> nil
      [id] -> repo.get!(Contact, id)
      _ -> repo.rollback({:contacts, :source_identity_conflict})
    end
  end

  defp preserve_human_fields(nil, attrs), do: attrs

  defp preserve_human_fields(existing, attrs) do
    attrs =
      Enum.reduce([:name, :city], attrs, fn field, acc ->
        observed = blank_to_nil(existing.source_data[Atom.to_string(field)])

        if Map.get(existing, field) != observed,
          do: Map.put(acc, field, Map.get(existing, field)),
          else: acc
      end)

    attrs = %{
      attrs
      | source_data:
          Map.merge(Map.take(existing.source_data, ["historical_dates"]), attrs.source_data)
          |> preserve_confirmed_geography(existing.source_data)
    }

    previous_status = classification(existing.source_data["status"])

    if attrs.classification == "do_not_contact",
      do: Map.put(attrs, :classification, "do_not_contact"),
      else:
        if(
          existing.classification == "do_not_contact" or
            existing.classification != previous_status,
          do: Map.put(attrs, :classification, existing.classification),
          else: attrs
        )
  end

  defp preserve_confirmed_geography(data, %{"region_source" => "operator_confirmed"} = previous),
    do: Map.merge(data, Map.take(previous, ~w(geography region_source)))

  defp preserve_confirmed_geography(data, _), do: data

  defp classification(value) when value in ["known_active", "active"], do: "known_active"
  defp classification("do_not_contact"), do: "do_not_contact"
  defp classification(_), do: "needs_review"
  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: if(String.trim(value) == "", do: nil, else: String.trim(value))

  defp source_key(row) do
    blank_to_nil(row["source_key"]) || blank_to_nil(row["discord_user_id"]) ||
      blank_to_nil(row["discord"])
  end

  defp source_data(row) do
    row
    |> Map.drop(~w(id row valid))
    |> Map.reject(fn {_key, value} -> value in [nil, ""] end)
  end
end
