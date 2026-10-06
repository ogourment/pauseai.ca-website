defmodule PauseAiCa.CRM do
  @moduledoc "Local identity adapter. Historical identities are superadmin-only; account authority stays separate."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.CRM.ContactLink
  alias PauseAiCa.ContactMigration.{Contact, Activity}

  def context, do: PhoenixCRM.new(Repo, PauseAiCa.CRM.Policy)
  def get(scope, id), do: PhoenixCRM.get(context(), scope, id)
  def search(scope, term), do: PhoenixCRM.search(context(), scope, term)
  require PauseAiCa.ContactMigration.Geography
  alias PauseAiCa.ContactMigration.Geography

  @directory_sizes [10, 25, 50, 100]

  # Directory reads are paged by canonical person, never by address or source row.
  # Batch hydration avoids loading profile activity for every search result.
  def directory_page(scope, params) do
    if Volunteers.superadmin?(scope) do
      query_text = String.slice(directory_string(params["q"]), 0, 500)
      region = String.slice(directory_string(params["region"]), 0, 200)
      per = positive_integer(params["per"], 25)
      per = if per in @directory_sizes, do: per, else: 25
      pattern = "%" <> escape_search(query_text) <> "%"

      matches =
        from p in PhoenixCRM.Person,
          left_join: alias_person in PhoenixCRM.Person,
          on: alias_person.id == p.id or alias_person.canonical_id == p.id,
          left_join: address in PhoenixCRM.Address,
          on: address.person_id == alias_person.id,
          left_join: link in ContactLink,
          on: link.person_id == alias_person.id,
          left_join: contact in Contact,
          on: contact.id == link.contact_id,
          where: is_nil(p.canonical_id),
          select: p.id,
          distinct: true

      matches =
        if query_text == "" do
          matches
        else
          from [p, ap, a, l, c] in matches,
            where:
              ilike(p.name, ^pattern) or ilike(p.city, ^pattern) or
                ilike(ap.name, ^pattern) or ilike(ap.city, ^pattern) or
                ilike(a.email, ^pattern) or ilike(c.name, ^pattern) or
                ilike(c.city, ^pattern) or ilike(c.email, ^pattern) or
                ilike(
                  Geography.expression(c.source_data),
                  ^pattern
                ) or
                fragment(
                  "EXISTS (SELECT 1 FROM jsonb_each_text(COALESCE(?, '{}'::jsonb)) AS field WHERE field.value ILIKE ?)",
                  c.source_data,
                  ^pattern
                )
        end

      matches =
        if region == "" do
          matches
        else
          from [p, ap, a, l, c] in matches,
            where: Geography.expression(c.source_data) == ^region
        end

      people = from p in PhoenixCRM.Person, where: p.id in subquery(matches)
      total = Repo.aggregate(people, :count)
      pages = max(1, div(total + per - 1, per))
      page = min(positive_integer(params["page"], 1), pages)

      selected =
        Repo.all(
          from p in people,
            order_by: [asc: p.name, asc: p.id],
            limit: ^per,
            offset: ^((page - 1) * per)
        )

      ids = Enum.map(selected, & &1.id)

      aliases =
        Repo.all(from p in PhoenixCRM.Person, where: p.id in ^ids or p.canonical_id in ^ids)

      alias_ids = Enum.map(aliases, & &1.id)

      addresses =
        Repo.all(
          from a in PhoenixCRM.Address, where: a.person_id in ^alias_ids, order_by: a.email
        )

      grouped_aliases = Enum.group_by(aliases, &(&1.canonical_id || &1.id), & &1.id)
      grouped_addresses = Enum.group_by(addresses, & &1.person_id)

      records =
        for person <- selected do
          person_aliases = Map.fetch!(grouped_aliases, person.id)

          %{
            person: person,
            aliases: person_aliases,
            addresses: Enum.flat_map(person_aliases, &Map.get(grouped_addresses, &1, []))
          }
        end

      regions =
        Repo.all(
          from c in Contact,
            join: l in ContactLink,
            on: l.contact_id == c.id,
            select: Geography.expression(c.source_data),
            distinct: true
        )
        |> Enum.reject(&is_nil/1)

      if Volunteers.superadmin?(scope) do
        {:ok,
         %{
           records: records,
           total: total,
           pages: pages,
           page: page,
           per: per,
           q: query_text,
           region: region,
           regions: Enum.uniq(["Montréal", "ROQuébec", "ROCanada" | regions]) |> Enum.sort()
         }}
      else
        {:error, :unauthorized}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp directory_string(value) when is_binary(value), do: value
  defp directory_string(_), do: ""

  defp positive_integer(value, default) when is_binary(value) and byte_size(value) < 12 do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp positive_integer(_, default), do: default

  defp escape_search(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  def compare(scope, a, b), do: PhoenixCRM.compare(context(), scope, a, b)

  def merge(scope, comparison, decisions),
    do: PhoenixCRM.merge(context(), scope, comparison, decisions)

  def undo(scope, id), do: PhoenixCRM.undo(context(), scope, id)

  def update(scope, record, attrs),
    do: PhoenixCRM.update(context(), scope, record.person.id, record.person.revision, attrs)

  def observe(scope, attrs, source, key) do
    PhoenixCRM.import(context(), scope, Map.take(attrs, ~w(email name city)), %{
      source: source,
      external_key: key,
      observed_at: DateTime.utc_now()
    })
  end

  # Called explicitly inside the historical import transaction; no account creation or send.
  def link_contact(scope, %Contact{} = contact) do
    if Volunteers.superadmin?(scope) do
      Repo.transaction(fn ->
        case Repo.get_by(ContactLink, contact_id: contact.id) do
          nil ->
            attrs = %{"email" => contact.email, "name" => contact.name, "city" => contact.city}

            case observe(scope, attrs, contact.source, contact.source_key || contact.id) do
              {:ok, record} ->
                Repo.insert!(%ContactLink{contact_id: contact.id, person_id: record.person.id})

              {:error, error} ->
                Repo.rollback(error)
            end

          link ->
            case observe(
                   scope,
                   %{"email" => contact.email, "name" => contact.name, "city" => contact.city},
                   contact.source,
                   contact.source_key || contact.id
                 ) do
              {:ok, _} -> link
              {:error, error} -> Repo.rollback(error)
            end
        end
      end)
    else
      {:error, :unauthorized}
    end
  end

  def get_legacy(scope, id) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, _} <- Ecto.UUID.cast(id),
         %ContactLink{} = link <- Repo.get_by(ContactLink, contact_id: id) do
      get(scope, link.person_id)
    else
      _ -> {:error, :unauthorized}
    end
  end

  def origins(scope, id) do
    with {:ok, record} <- get(scope, id) do
      ids = record.aliases

      Repo.all(
        from c in Contact,
          join: l in ContactLink,
          on: l.contact_id == c.id,
          where: l.person_id in ^ids,
          order_by: c.id
      )
    else
      _ -> []
    end
  end

  # Load all displayed origins once, including aliases retained by reconciliation.
  def directory_origins(scope, records) do
    if Volunteers.superadmin?(scope) do
      owners = for record <- records, id <- record.aliases, into: %{}, do: {id, record.person.id}
      ids = Map.keys(owners)

      origins =
        Repo.all(
          from c in Contact,
            join: l in ContactLink,
            on: l.contact_id == c.id,
            where: l.person_id in ^ids,
            order_by: c.id,
            select: {l.person_id, c}
        )
        |> Enum.group_by(fn {id, _} -> Map.fetch!(owners, id) end, fn {_, contact} -> contact end)

      {:ok, origins}
    else
      {:error, :unauthorized}
    end
  end

  def legacy_activities(scope, id) do
    ids = Enum.map(origins(scope, id), & &1.id)

    Repo.all(
      from a in Activity, where: a.contact_id in ^ids, order_by: [desc: a.inserted_at, desc: a.id]
    )
  end

  def merges(scope, id) do
    with {:ok, record} <- get(scope, id) do
      Repo.all(
        from m in PhoenixCRM.Merge,
          where: m.person_id == ^record.person.id,
          order_by: [desc: m.inserted_at, desc: m.id]
      )
    else
      _ -> []
    end
  end
end
