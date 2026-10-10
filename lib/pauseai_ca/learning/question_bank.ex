defmodule PauseAiCa.Learning.QuestionBank do
  @moduledoc "Shared quiz CMS with editorial drafts and explicit, stable publication snapshots."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Learning.QuestionDraft

  @fields ~w(question options correct answer source url action notes image_url image_alt image_credit social_proof language)

  def list(scope, filter \\ "all") do
    if Volunteers.allowed?(scope) do
      query = from q in QuestionDraft, order_by: [asc: q.review_id]

      query =
        if filter == "deleted",
          do: from(q in query, where: not is_nil(q.deleted_at)),
          else: from(q in query, where: is_nil(q.deleted_at))

      query =
        if filter in ["draft", "published"],
          do: from(q in query, where: q.status == ^filter),
          else: query

      Repo.all(query)
    else
      []
    end
  end

  def published(locale) when locale in ["en", "fr"] do
    Repo.all(
      from q in QuestionDraft,
        where: q.status == "published" and is_nil(q.deleted_at),
        order_by: [asc: q.review_id]
    )
    |> Enum.flat_map(fn q ->
      case q.published_editions[locale] do
        nil ->
          []

        edition ->
          [
            %{
              id: q.id,
              review_id: q.review_id,
              concept_id: q.concept_id,
              revision: q.published_revision,
              topic: q.published_topic,
              kind: q.published_kind,
              edition: Map.drop(edition, ["notes", "social_proof"])
            }
          ]
      end
    end)
  end

  def published(_), do: []

  def catalogue(locale) do
    managed = Repo.all(from q in QuestionDraft, where: not is_nil(q.published_revision))

    replacements =
      managed
      |> Enum.filter(&(&1.status == "published" and is_nil(&1.deleted_at)))
      |> Enum.flat_map(fn q ->
        case q.published_editions[locale] do
          nil -> []
          edition -> [nugget(q, edition, locale)]
        end
      end)

    managed_ids = Enum.map(managed, & &1.concept_id)

    (Enum.reject(PauseAiCa.Learning.nuggets(locale), &(&1["id"] in managed_ids)) ++ replacements)
    |> Enum.sort_by(&(&1["language"] != locale))
  end

  def valid_ids(ids) when is_list(ids) do
    allowed = Enum.uniq(Enum.map(catalogue("en") ++ catalogue("fr"), & &1["id"]))
    ids |> Enum.filter(&(&1 in allowed)) |> Enum.uniq()
  end

  def valid_ids(_), do: []

  # Previously published snapshots keep saved reading links useful after retirement.
  def resource(id) do
    with {:ok, _} <- Ecto.UUID.cast(id),
         %QuestionDraft{} = q <- Repo.get_by(QuestionDraft, concept_id: id),
         false <- is_nil(q.published_revision) do
      editions = q.published_editions
      first = editions["en"] || editions["fr"]

      %PauseAiCa.Library.Resource{
        id: id,
        stage: :curiosity,
        format: :article,
        language: "en",
        url: first["url"],
        publisher: first["source"],
        reviewed_on: DateTime.to_date(q.published_at),
        copy:
          Map.new(["en", "fr"], fn locale ->
            edition = editions[locale] || first
            {locale, %{title: edition["question"], summary: edition["answer"]}}
          end)
      }
    else
      _ -> nil
    end
  end

  defp source_language(id, edition, locale) do
    original = Enum.find(PauseAiCa.Learning.nuggets(locale), &(&1["id"] == id)) || %{}

    cond do
      edition["language"] in ["en", "fr"] -> edition["language"]
      edition["url"] == original["url"] -> original["language"] || locale
      true -> locale
    end
  end

  defp nugget(question, edition, locale) do
    original =
      Enum.find(PauseAiCa.Learning.nuggets(locale), &(&1["id"] == question.concept_id)) || %{}

    language = source_language(question.concept_id, edition, locale)

    original
    |> Map.merge(Map.drop(edition, ["notes", "social_proof"]))
    |> Map.merge(%{
      "id" => question.concept_id,
      "title" => original["title"] || edition["question"],
      "topic" =>
        if(question.published_topic == "actions", do: "treaty", else: question.published_topic),
      "discussion" => question.published_kind != "factual",
      "evidence" => if(edition["url"] == original["url"], do: original["evidence"], else: nil),
      "cms" => true,
      "language" => language || locale
    })
  end

  def unpublished_changes?(question),
    do: question.status == "published" and question.revision != question.published_revision

  def get(scope, id) do
    with true <- Volunteers.allowed?(scope),
         {:ok, _} <- Ecto.UUID.cast(id),
         %QuestionDraft{} = draft <- Repo.get(QuestionDraft, id),
         do: {:ok, draft},
         else: (_ -> {:error, :unauthorized})
  end

  def create(scope) do
    if Volunteers.allowed?(scope) do
      id = Ecto.UUID.generate()

      %QuestionDraft{}
      |> QuestionDraft.changeset(%{
        review_id: "LEARN-DRAFT-" <> id,
        concept_id: id,
        updated_by: scope.user.id
      })
      |> Repo.insert()
    else
      {:error, :unauthorized}
    end
  end

  def values(draft, locale) do
    edition = Map.get(draft.editions, locale, %{})

    Map.merge(Map.new(@fields, &{&1, ""}), edition)
    |> Map.put("options", Enum.join(edition["options"] || [], "\n"))
    |> Map.put(
      "correct",
      if(is_integer(edition["correct"]), do: to_string(edition["correct"]), else: "")
    )
    |> Map.put(
      "language",
      edition["language"] || source_language(draft.concept_id, edition, locale)
    )
    |> Map.put("kind", draft.kind)
    |> Map.put("topic", if(draft.topic == "actions", do: "treaty", else: draft.topic))
  end

  def save(scope, draft, locale, attrs) when locale in ["en", "fr"] do
    with true <- Volunteers.allowed?(scope),
         {:ok, persisted} <- get(scope, draft.id),
         true <- persisted.revision == draft.revision and is_nil(persisted.deleted_at),
         {:ok, edition} <- edition(attrs) do
      changed = Map.put(persisted.editions, locale, edition)

      changeset =
        QuestionDraft.changeset(draft, %{
          editions: changed,
          kind: attrs["kind"] || draft.kind,
          topic: attrs["topic"] || draft.topic,
          updated_by: scope.user.id
        })

      persist(changeset, scope)
    else
      false -> if(Volunteers.allowed?(scope), do: {:error, :stale}, else: {:error, :unauthorized})
      error -> error
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  def save(_, _, _, _), do: {:error, :invalid}

  def publish(scope, question), do: transition(scope, question, :publish)
  def move_to_draft(scope, question), do: transition(scope, question, :draft)
  def delete(scope, question), do: transition(scope, question, :delete)
  def restore(scope, question), do: transition(scope, question, :restore)

  defp transition(scope, question, action) do
    with {:ok, current} <- get(scope, question.id),
         true <- current.revision == question.revision,
         {:ok, attrs} <- transition_attrs(current, action) do
      current
      |> QuestionDraft.changeset(Map.put(attrs, :updated_by, scope.user.id))
      |> persist(scope)
    else
      false -> {:error, :stale}
      error -> error
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  defp transition_attrs(%{deleted_at: deleted}, :publish) when not is_nil(deleted),
    do: {:error, :deleted}

  defp transition_attrs(question, :publish) do
    errors = publication_errors(question)

    if errors == [],
      do:
        {:ok,
         %{
           status: "published",
           published_editions: question.editions,
           published_kind: question.kind,
           published_topic: question.topic,
           published_revision: question.revision + 1,
           published_at: DateTime.utc_now()
         }},
      else: {:error, {:publication_invalid, errors}}
  end

  defp transition_attrs(%{deleted_at: nil}, :draft), do: {:ok, %{status: "draft"}}
  defp transition_attrs(%{status: "published"}, :delete), do: {:error, :published}
  defp transition_attrs(_, :delete), do: {:ok, %{deleted_at: DateTime.utc_now()}}
  defp transition_attrs(_, :restore), do: {:ok, %{deleted_at: nil, status: "draft"}}
  defp transition_attrs(_, _), do: {:error, :invalid}

  defp publication_errors(question) do
    editions = Map.take(question.editions, ["en", "fr"])

    if editions == %{},
      do: [{"en", "question"}],
      else:
        Enum.flat_map(editions, fn {locale, edition} ->
          missing = Enum.filter(~w(question answer source url), &blank?(edition[&1]))
          choices = edition["options"] || []
          correct = edition["correct"]

          missing =
            if question.kind == "factual" and
                 (length(choices) < 2 or not is_integer(correct) or correct < 0 or
                    correct >= length(choices)), do: missing ++ ["correct"], else: missing

          missing =
            if question.kind != "factual" and not is_nil(correct),
              do: missing ++ ["correct"],
              else: missing

          missing =
            if not blank?(edition["image_url"]) and blank?(edition["image_alt"]),
              do: missing ++ ["image_alt"],
              else: missing

          Enum.map(Enum.uniq(missing), &{locale, &1})
        end)
  end

  defp blank?(value), do: value in [nil, ""] or (is_binary(value) and String.trim(value) == "")

  defp persist(%Ecto.Changeset{valid?: true, changes: changes, data: question}, _scope)
       when map_size(changes) == 0, do: {:ok, question}

  defp persist(changeset, scope) do
    PhoenixCMS.Revisions.update(Repo, changeset, PauseAiCa.Learning.QuestionRevision, fn saved ->
      %{
        question_id: saved.id,
        revision: saved.revision,
        editor_id: scope.user.id,
        editions: saved.editions,
        kind: saved.kind,
        topic: saved.topic,
        status: saved.status,
        published_editions: saved.published_editions,
        inserted_at: DateTime.utc_now()
      }
    end)
  end

  defp edition(attrs) do
    values = Map.take(attrs, @fields)

    bounded? =
      Enum.all?(values, fn {_, value} -> is_binary(value) and byte_size(value) <= 20_000 end)

    if bounded? do
      options = String.split(values["options"] || "", "\n", trim: true)

      correct =
        case Integer.parse(values["correct"] || "") do
          {n, ""} -> n
          _ -> nil
        end

      urls? = Enum.all?([values["url"], values["image_url"]], &safe_url?/1)

      if urls? and values["language"] in [nil, "", "en", "fr"] and length(options) <= 12 and
           (is_nil(correct) or (correct >= 0 and correct < length(options))) do
        {:ok, values |> Map.put("options", options) |> Map.put("correct", correct)}
      else
        {:error, :invalid}
      end
    else
      {:error, :invalid}
    end
  end

  defp safe_url?(value) when value in [nil, ""], do: true
  defp safe_url?("/images/" <> rest), do: not String.contains?(rest, ["..", "\\", "\n", "\r"])

  defp safe_url?("/en/" <> rest), do: safe_internal_path?(rest)
  defp safe_url?("/fr/" <> rest), do: safe_internal_path?(rest)

  defp safe_url?(value) do
    uri = URI.parse(value)

    uri.scheme in ["https", "http"] and is_binary(uri.host) and uri.host != "" and
      is_nil(uri.userinfo)
  end

  defp safe_internal_path?(rest),
    do:
      not String.contains?(rest, ["..", "\\", "\n", "\r"]) and not String.starts_with?(rest, "/")
end
