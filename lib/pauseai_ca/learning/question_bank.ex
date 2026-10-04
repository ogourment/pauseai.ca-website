defmodule PauseAiCa.Learning.QuestionBank do
  @moduledoc "Shared editorial drafts; public quizzes never read this table."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Learning.QuestionDraft

  @fields ~w(question options correct answer source url action notes image_url image_alt image_credit social_proof)

  def list(scope) do
    if Volunteers.allowed?(scope),
      do: Repo.all(from q in QuestionDraft, order_by: [asc: q.review_id]),
      else: []
  end

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
    |> Map.put("kind", draft.kind)
    |> Map.put("topic", draft.topic)
  end

  def save(scope, draft, locale, attrs) when locale in ["en", "fr"] do
    with true <- Volunteers.allowed?(scope),
         {:ok, persisted} <- get(scope, draft.id),
         true <- persisted.revision == draft.revision,
         {:ok, edition} <- edition(attrs) do
      changed = Map.put(persisted.editions, locale, edition)

      changeset =
        QuestionDraft.changeset(draft, %{
          editions: changed,
          kind: attrs["kind"] || draft.kind,
          topic: attrs["topic"] || draft.topic,
          updated_by: scope.user.id
        })

      Repo.transaction(fn ->
        case Repo.update(changeset) do
          {:ok, saved} ->
            Repo.insert_all(PauseAiCa.Learning.QuestionRevision, [
              %{
                question_id: saved.id,
                revision: saved.revision,
                editor_id: scope.user.id,
                editions: saved.editions,
                kind: saved.kind,
                inserted_at: DateTime.utc_now()
              }
            ])

            saved

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
    else
      false -> if(Volunteers.allowed?(scope), do: {:error, :stale}, else: {:error, :unauthorized})
      error -> error
    end
  rescue
    Ecto.StaleEntryError -> {:error, :stale}
  end

  def save(_, _, _, _), do: {:error, :invalid}

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

      if urls? and length(options) <= 12 and
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

  defp safe_url?(value) do
    uri = URI.parse(value)

    uri.scheme in ["https", "http"] and is_binary(uri.host) and uri.host != "" and
      is_nil(uri.userinfo)
  end
end
