defmodule PauseAiCa.Donations.Pages do
  @moduledoc "Superadmin-authored donation content. Drafts, immutable CMS history and the public snapshot remain separate."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Donations.{Page, PageRevision, PagePayload}

  def permitted?(scope), do: Volunteers.superadmin?(scope)
  def defaults, do: PagePayload.defaults()
  def edition_fields, do: PagePayload.edition_fields()

  @doc "Read only; no row/default is persisted by a public request."
  def published do
    Repo.one(from p in Page, where: p.key == "main", select: p.published_payload)
  end

  def get_or_create(scope) do
    authorized(scope, fn ->
      Repo.transaction(fn ->
        lock_and_authorize(scope)

        case Repo.one(from p in Page, where: p.key == "main", lock: "FOR UPDATE") do
          nil ->
            page = Repo.insert!(%Page{key: "main"})
            persist(page, %{payload: defaults(), updated_by: scope.user.id}, scope, "created")

          page ->
            page
        end
      end)
    end)
  end

  def preview(scope, payload) do
    authorized(scope, fn -> PagePayload.validate(payload, :draft) end)
  end

  def save(scope, %Page{} = page, payload) do
    mutate(scope, page, fn current ->
      case PagePayload.validate(payload, :draft) do
        {:ok, validated} ->
          persist(current, %{payload: validated, updated_by: scope.user.id}, scope, "saved")

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def publish(scope, %Page{} = page) do
    mutate(scope, page, fn current ->
      case PagePayload.validate(current.payload, :publish) do
        {:ok, validated} ->
          persist(
            current,
            %{
              published_payload: validated,
              published_revision: current.revision + 1,
              published_at: DateTime.utc_now(),
              updated_by: scope.user.id
            },
            scope,
            "published"
          )

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def history(scope) do
    authorized(scope, fn ->
      {:ok,
       Repo.all(
         from r in PageRevision,
           join: p in Page,
           on: p.id == r.page_id,
           where: p.key == "main",
           order_by: [desc: r.revision]
       )}
    end)
  end

  def restore(scope, %Page{} = page, revision_id) do
    mutate(scope, page, fn current ->
      case Ecto.UUID.cast(revision_id) do
        {:ok, id} ->
          case Repo.get_by(PageRevision, id: id, page_id: current.id) do
            nil ->
              Repo.rollback(:not_found)

            revision ->
              persist(
                current,
                %{payload: revision.payload, updated_by: scope.user.id},
                scope,
                "restored"
              )
          end

        _ ->
          Repo.rollback(:not_found)
      end
    end)
  end

  defp mutate(scope, page, fun) do
    authorized(scope, fn ->
      Repo.transaction(fn ->
        lock_and_authorize(scope)

        case Repo.one(from p in Page, where: p.key == "main", lock: "FOR UPDATE") do
          %Page{id: id, revision: revision} = current
          when id == page.id and revision == page.revision ->
            fun.(current)

          nil ->
            Repo.rollback(:not_found)

          _ ->
            Repo.rollback(:stale)
        end
      end)
    end)
  end

  defp authorized(scope, fun) do
    if permitted?(scope), do: fun.(), else: {:error, :unauthorized}
  end

  defp lock_and_authorize(scope) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended('donation-page:main', 0))")
    unless permitted?(scope), do: Repo.rollback(:unauthorized)
  end

  defp persist(page, attrs, scope, action) do
    changeset = Page.changeset(page, attrs)

    case PhoenixCMS.Revisions.update(Repo, changeset, PageRevision, fn saved ->
           %{
             id: Ecto.UUID.generate(),
             page_id: saved.id,
             revision: saved.revision,
             editor_id: scope.user.id,
             action: action,
             payload: saved.payload,
             published_payload: saved.published_payload,
             published_revision: saved.published_revision,
             inserted_at: DateTime.utc_now()
           }
         end) do
      {:ok, saved} -> saved
      {:error, reason} -> Repo.rollback(reason)
    end
  end
end
