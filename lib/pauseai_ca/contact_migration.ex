defmodule PauseAiCa.ContactMigration do
  import Ecto.Query

  alias Ecto.Multi
  alias PauseAiCa.Accounts.User
  alias PauseAiCa.ContactMigration.{Activity, Contact, Import}
  alias PauseAiCa.Repo

  def list_contacts(search \\ "") do
    list_contacts_page(search, 1, 100_000).entries
  end

  def list_contacts_page(search \\ "", page \\ 1, page_size \\ 25) do
    pattern = "%#{String.replace(search, "%", "\\%")}%"

    query =
      from(c in Contact,
        left_join: u in assoc(c, :user),
        where:
          ilike(c.email, ^pattern) or ilike(coalesce(c.name, ""), ^pattern) or
            ilike(coalesce(c.city, ""), ^pattern),
        preload: [user: u],
        order_by: [asc: c.email]
      )

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

  def import_selected(rows, filename, source, actor) do
    Multi.new()
    |> Multi.insert(
      :import,
      Import.changeset(%Import{}, %{
        filename: filename,
        source: source,
        selected_count: length(rows),
        imported_by_id: actor.id
      })
    )
    |> Multi.run(:contacts, fn repo, %{import: import} ->
      {:ok, Enum.map(rows, &upsert_contact(repo, &1, source, import.id, actor.id))}
    end)
    |> Repo.transaction()
  end

  defp upsert_contact(repo, row, source, import_id, actor_id) do
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

    contact =
      case repo.get_by(Contact, email: email) do
        nil -> %Contact{}
        existing -> existing
      end
      |> Contact.changeset(attrs)
      |> repo.insert_or_update!()

    %Activity{}
    |> Activity.changeset(%{
      contact_id: contact.id,
      actor_user_id: actor_id,
      action: "imported",
      details: %{"account_match" => not is_nil(user), "import_id" => import_id}
    })
    |> repo.insert!()

    contact
  end

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
