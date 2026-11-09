defmodule PauseAiCa.MPTemplates do
  @moduledoc "Consumer-owned campaign templates, attributed CMS history and public frozen editions."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers, Accounts.User}
  alias PauseAiCa.MPTemplates.{Template, Revision, Payload}

  def permitted?(scope), do: Volunteers.superadmin?(scope)
  def empty_payload, do: Payload.empty()

  @doc "Aggregate accepted website sends and explicitly confirmed external handoffs. No identities are disclosed."
  def completed_count(template_id) do
    case Ecto.UUID.cast(template_id) do
      {:ok, id} ->
        Repo.aggregate(
          from(intent in PauseAiCa.Campaigns.SendIntent,
            left_join: action in PauseAiCa.Engagement.Action,
            on: action.id == intent.action_id and action.user_id == intent.actor_id,
            where: intent.template_id == ^id,
            where:
              (intent.state == "accepted" and not is_nil(intent.accepted_at)) or
                (intent.state == "handoff" and not is_nil(action.confirmed_at))
          ),
          :count
        )

      :error ->
        0
    end
  end

  def variables, do: Payload.variables()

  def list(scope) do
    if permitted?(scope),
      do: {:ok, Repo.all(from t in Template, order_by: [desc: t.updated_at])},
      else: {:error, :unauthorized}
  end

  def get(scope, id) do
    with true <- permitted?(scope),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %Template{} = template <- Repo.get(Template, uuid),
         do: {:ok, template},
         else: (_ -> {:error, :not_found})
  end

  def history(scope, %Template{id: id}) do
    if permitted?(scope),
      do:
        {:ok,
         Repo.all(from r in Revision, where: r.template_id == ^id, order_by: [desc: r.revision])},
      else: {:error, :unauthorized}
  end

  def create(scope, slug) when is_binary(slug) do
    authorized(scope, fn ->
      case Repo.insert(
             Template.changeset(%Template{}, %{
               slug: slug,
               payload: Payload.empty(),
               updated_by: scope.user.id
             })
           ) do
        {:ok, template} ->
          snapshot(template, scope, "created", false)
          template

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def create(_, _), do: {:error, :invalid_slug}

  def save(scope, %Template{} = template, payload) do
    mutate(scope, template, fn current ->
      case Payload.validate(payload, :draft) do
        {:ok, normalized} -> persist(current, %{payload: normalized}, scope, "saved", false)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def publish(scope, %Template{} = template, acknowledgement) do
    mutate(scope, template, fn current ->
      unless acknowledgement in [true, "true"], do: Repo.rollback(:author_permission_required)

      case Payload.validate(current.payload, :publish) do
        {:ok, normalized} ->
          persist(
            current,
            %{
              payload: normalized,
              published_revision: current.revision + 1,
              published_at: DateTime.utc_now()
            },
            scope,
            "published",
            true
          )

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc "Return only a published, author-permitted immutable edition. An explicit revision never falls back."
  def published(slug, locale, revision \\ nil)

  def published(slug, locale, revision)
      when is_binary(slug) and byte_size(slug) <= 80 and locale in ["en", "fr"] do
    with %Template{published_revision: published} = template when is_integer(published) <-
           Repo.get_by(Template, slug: slug),
         {:ok, number} <- revision_number(revision, published),
         %Revision{} = snapshot <-
           Repo.one(
             from r in Revision,
               where:
                 r.template_id == ^template.id and r.revision == ^number and
                   r.action == "published" and r.author_permission == true
           ),
         {:ok, payload} <- Payload.validate(snapshot.payload, :publish) do
      edition = payload["editions"][locale]

      {:ok,
       %{
         id: template.id,
         slug: template.slug,
         revision: snapshot.revision,
         locale: locale,
         title: edition["title"],
         purpose: edition["purpose"],
         subject: edition["subject"],
         body: edition["body"],
         author: payload["author"],
         source: payload["source"],
         html: PauseAiCa.Mail.Render.html(edition["body"]),
         share_path: share_path(template.slug, locale, snapshot.revision)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  def published(_, _, _), do: {:error, :not_found}

  def share_path(slug, locale, revision) do
    prefix = if locale == "fr", do: "/fr/modeles-de-lettre/", else: "/en/mp-templates/"
    prefix <> URI.encode(slug, &URI.char_unreserved?/1) <> "?revision=" <> to_string(revision)
  end

  defp revision_number(nil, latest), do: {:ok, latest}

  defp revision_number(value, _) when is_integer(value) and value > 0 and value <= 2_147_483_647,
    do: {:ok, value}

  defp revision_number(value, latest) when is_binary(value) and byte_size(value) <= 10 do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> revision_number(number, latest)
      _ -> {:error, :not_found}
    end
  end

  defp revision_number(_, _), do: {:error, :not_found}

  defp authorized(scope, fun) do
    if permitted?(scope) do
      Repo.transaction(fn ->
        Repo.one!(from u in User, where: u.id == ^scope.user.id, lock: "FOR SHARE")
        unless permitted?(scope), do: Repo.rollback(:unauthorized)
        fun.()
      end)
    else
      {:error, :unauthorized}
    end
  end

  defp mutate(scope, template, fun) do
    authorized(scope, fn ->
      case Repo.one(from t in Template, where: t.id == ^template.id, lock: "FOR UPDATE") do
        %Template{revision: revision} = current when revision == template.revision ->
          fun.(current)

        nil ->
          Repo.rollback(:not_found)

        _ ->
          Repo.rollback(:stale)
      end
    end)
  end

  defp persist(template, attrs, scope, action, permission) do
    attrs = Map.put(attrs, :updated_by, scope.user.id)

    case PhoenixCMS.Revisions.update(
           Repo,
           Template.changeset(template, attrs),
           Revision,
           fn saved ->
             revision_attributes(saved, scope, action, permission)
           end
         ) do
      {:ok, saved} -> saved
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp snapshot(template, scope, action, permission),
    do: Repo.insert_all(Revision, [revision_attributes(template, scope, action, permission)])

  defp revision_attributes(template, scope, action, permission),
    do: %{
      id: Ecto.UUID.generate(),
      template_id: template.id,
      revision: template.revision,
      editor_id: scope.user.id,
      action: action,
      payload: template.payload,
      author_permission: permission,
      inserted_at: DateTime.utc_now()
    }
end
