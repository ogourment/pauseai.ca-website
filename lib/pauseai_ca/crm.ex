defmodule PauseAiCa.CRM do
  @moduledoc "Local identity adapter. Historical identities are superadmin-only; account authority stays separate."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.CRM.ContactLink
  alias PauseAiCa.ContactMigration.{Contact, Activity}

  def context, do: PhoenixCRM.new(Repo, PauseAiCa.CRM.Policy)
  def get(scope, id), do: PhoenixCRM.get(context(), scope, id)
  def search(scope, term), do: PhoenixCRM.search(context(), scope, term)
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
