defmodule PauseAiCaWeb.LearningBasketController do
  use PauseAiCaWeb, :controller
  import Ecto.Query
  alias PauseAiCa.Repo
  alias PauseAiCa.Learning.QuestionBank
  alias PauseAiCa.Accounts.User

  def update(conn, params) do
    cond do
      is_nil(conn.assigns.current_scope) ->
        conn |> put_status(:unauthorized) |> json(%{error: "authentication_required"})

      params["operation"] not in ["merge", "add", "remove"] ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_operation"})

      true ->
        user_id = conn.assigns.current_scope.user.id

        result =
          Repo.transaction(fn ->
            user = Repo.one!(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE")
            id = params["id"]

            saved =
              case params["operation"] do
                "merge" ->
                  Enum.uniq(user.saved_resources ++ QuestionBank.valid_ids(params["ids"]))

                "add" ->
                  if QuestionBank.valid_ids([id]) != [],
                    do: Enum.uniq(user.saved_resources ++ [id]),
                    else: user.saved_resources

                "remove" ->
                  if id in user.saved_resources,
                    do: List.delete(user.saved_resources, id),
                    else: user.saved_resources
              end

            user |> Ecto.Changeset.change(saved_resources: saved) |> Repo.update!()
          end)

        case result do
          {:ok, user} ->
            json(conn, %{ids: user.saved_resources})

          {:error, _} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: "save_failed"})
        end
    end
  end
end
