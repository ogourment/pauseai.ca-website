defmodule PauseAiCa.Blog do
  @moduledoc "Consumer-owned bilingual articles, publication snapshots and immutable shared CMS history."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Blog.{Article, Revision}
  @fields ~w(title summary details full)

  def permitted?(scope), do: Volunteers.superadmin?(scope)
  def empty_payload, do: Map.new(~w(en fr), &{&1, Map.new(@fields, fn field -> {field, ""} end)})

  def published do
    Repo.all(
      from a in Article,
        where: not is_nil(a.published_payload) and is_nil(a.archived_at),
        order_by: [desc: a.published_at],
        select: %{slug: a.slug, payload: a.published_payload, published_at: a.published_at}
    )
  end

  def published(slug) do
    Repo.one(
      from a in Article,
        where: a.slug == ^slug and not is_nil(a.published_payload) and is_nil(a.archived_at),
        select: %{slug: a.slug, payload: a.published_payload, published_at: a.published_at}
    )
  end

  def list(scope),
    do:
      authorize(scope, fn ->
        {:ok,
         Repo.all(from a in Article, where: is_nil(a.archived_at), order_by: [desc: a.updated_at])}
      end)

  def get(scope, id), do: authorize(scope, fn -> {:ok, find(id)} end)

  def history(scope, article),
    do:
      authorize(scope, fn ->
        {:ok,
         Repo.all(
           from r in Revision, where: r.article_id == ^article.id, order_by: [desc: r.revision]
         )}
      end)

  def create(scope, slug) do
    authorize(scope, fn ->
      Repo.transaction(fn ->
        lock_authority(scope)

        case Repo.insert(
               Article.changeset(%Article{}, %{
                 slug: slug,
                 payload: empty_payload(),
                 updated_by: scope.user.id
               })
             ) do
          {:ok, article} -> persist(article, %{}, scope, "created")
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  def save(scope, article, payload) do
    mutate(scope, article, fn current ->
      case validate(payload, :draft) do
        :ok -> persist(current, %{payload: payload}, scope, "saved")
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def publish(scope, article) do
    mutate(scope, article, fn current ->
      case validate(current.payload, :publish) do
        :ok ->
          persist(
            current,
            %{
              published_payload:
                Map.filter(current.payload, fn {_locale, edition} -> complete?(edition) end),
              published_revision: current.revision + 1,
              published_at: DateTime.utc_now()
            },
            scope,
            "published"
          )

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  def unpublish(scope, article),
    do:
      mutate(
        scope,
        article,
        &persist(
          &1,
          %{published_payload: nil, published_revision: nil, published_at: nil},
          scope,
          "unpublished"
        )
      )

  def archive(scope, article),
    do:
      mutate(
        scope,
        article,
        &persist(
          &1,
          %{
            published_payload: nil,
            published_revision: nil,
            published_at: nil,
            archived_at: DateTime.utc_now()
          },
          scope,
          "archived"
        )
      )

  def restore(scope, article, id) do
    mutate(scope, article, fn current ->
      revision =
        case Ecto.UUID.cast(id) do
          {:ok, id} -> Repo.get_by(Revision, id: id, article_id: current.id)
          _ -> nil
        end

      if revision,
        do: persist(current, %{payload: revision.payload}, scope, "restored"),
        else: Repo.rollback(:not_found)
    end)
  end

  def validate(payload, mode) do
    valid =
      is_map(payload) and Enum.sort(Map.keys(payload)) == ~w(en fr) and
        Enum.all?(~w(en fr), fn locale ->
          edition = payload[locale]

          is_map(edition) and Enum.sort(Map.keys(edition)) == Enum.sort(@fields) and
            Enum.all?(@fields, fn field ->
              text = edition[field]

              is_binary(text) and String.valid?(text) and String.length(text) <= limit(field)
            end)
        end)

    if valid and (mode != :publish or Enum.any?(Map.values(payload), &complete?/1)),
      do: :ok,
      else: {:error, :invalid_content}
  end

  defp complete?(edition),
    do:
      Enum.all?(@fields, fn field ->
        is_binary(edition[field]) and String.trim(edition[field]) != ""
      end)

  defp limit("title"), do: 200
  defp limit("summary"), do: 1000
  defp limit(_), do: 100_000

  defp find(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.one(from a in Article, where: a.id == ^id and is_nil(a.archived_at))
      _ -> nil
    end
  end

  defp mutate(scope, article, fun) do
    authorize(scope, fn ->
      Repo.transaction(fn ->
        lock_authority(scope)

        case Repo.one(
               from a in Article,
                 where: a.id == ^article.id and is_nil(a.archived_at),
                 lock: "FOR UPDATE"
             ) do
          %Article{revision: revision} = current when revision == article.revision ->
            fun.(current)

          nil ->
            Repo.rollback(:not_found)

          _ ->
            Repo.rollback(:stale)
        end
      end)
    end)
  end

  defp authorize(scope, fun), do: if(permitted?(scope), do: fun.(), else: {:error, :unauthorized})

  defp lock_authority(scope) do
    # Hold the actor row while committing; concurrent revocation takes effect before the next mutation.
    Repo.query!("SELECT id FROM users WHERE id = $1 FOR SHARE", [Ecto.UUID.dump!(scope.user.id)])
    unless permitted?(scope), do: Repo.rollback(:unauthorized)
  end

  defp persist(article, attrs, scope, action) do
    changeset = Article.changeset(article, Map.put(attrs, :updated_by, scope.user.id))

    case PhoenixCMS.Revisions.update(Repo, changeset, Revision, fn saved ->
           %{
             id: Ecto.UUID.generate(),
             article_id: saved.id,
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
