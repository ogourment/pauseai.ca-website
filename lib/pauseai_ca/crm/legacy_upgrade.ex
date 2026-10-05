defmodule PauseAiCa.CRM.LegacyUpgrade do
  @moduledoc "Derives CRM identities for already-stored contacts during a schema upgrade; never reimports their business records."
  import Ecto.Query
  alias PauseAiCa.ContactMigration.Contact
  alias PauseAiCa.CRM.ContactLink
  @actor {:legacy_identity_upgrade, 20_261_005_045_000}

  defmodule Policy do
    @moduledoc false
    @behaviour PhoenixCRM.Policy
    import Ecto.Query
    def authorize({:legacy_identity_upgrade, 20_261_005_045_000}, :import, _), do: :ok
    def authorize(_, _, _), do: {:error, :unauthorized}
    def scope(_, query), do: where(query, [p], false)
    def actor_id({:legacy_identity_upgrade, 20_261_005_045_000}), do: "migration:20261005045000"
    def recipient(_, _, _), do: {:error, :ineligible}
  end

  def run(repo) do
    repo.transaction(fn ->
      repo.query!("SELECT pg_advisory_xact_lock(hashtext('pauseai-contact-import'))")

      linked = from l in ContactLink, select: l.contact_id

      contacts =
        repo.all(
          from c in Contact,
            where: c.id not in subquery(linked),
            order_by: c.id,
            lock: "FOR UPDATE"
        )

      context = PhoenixCRM.new(repo, Policy)

      for contact <- contacts do
        attrs = %{"email" => contact.email, "name" => contact.name, "city" => contact.city}

        observation = %{
          source: contact.source,
          external_key: contact.source_key || contact.id,
          observed_at: DateTime.utc_now()
        }

        case PhoenixCRM.import(context, @actor, attrs, observation) do
          {:ok, record} ->
            repo.insert!(%ContactLink{contact_id: contact.id, person_id: record.person.id})

          {:error, reason} ->
            repo.rollback(reason)
        end
      end

      length(contacts)
    end)
  end
end
