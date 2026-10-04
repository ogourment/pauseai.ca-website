defmodule PauseAiCaWeb.RogueProgressController do
  use PauseAiCaWeb, :controller
  import Ecto.Query
  alias PauseAiCa.Repo
  alias PauseAiCa.Engagement.GameAttempt

  def update(conn, params) do
    visitor = conn.assigns.learning_visitor_id
    user = conn.assigns.current_scope && conn.assigns.current_scope.user

    attrs =
      params
      |> Map.take(~w(id locale sequence furthest_stage completed buttons))
      |> Map.put("visitor_id", visitor)
      |> Map.put("user_id", user && user.id)

    changeset = GameAttempt.changeset(%GameAttempt{}, attrs)
    # Duplicate and out-of-order snapshots cannot inflate counts or regress progress.
    # Ownership is server-derived; an ID from another browser cannot be overwritten.
    owner_id = if user, do: user.id, else: "00000000-0000-0000-0000-000000000000"

    query =
      from(a in GameAttempt,
        where:
          a.visitor_id == ^visitor and (is_nil(a.user_id) or a.user_id == ^owner_id) and
            a.sequence < fragment("EXCLUDED.sequence"),
        update: [
          set: [
            sequence: fragment("EXCLUDED.sequence"),
            furthest_stage: fragment("GREATEST(?, EXCLUDED.furthest_stage)", a.furthest_stage),
            completed: fragment("? OR EXCLUDED.completed", a.completed),
            buttons: fragment("EXCLUDED.buttons"),
            updated_at: fragment("EXCLUDED.updated_at")
          ]
        ]
      )

    case Repo.insert(changeset, on_conflict: query, conflict_target: [:id], allow_stale: true) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, _} -> conn |> put_status(:unprocessable_entity) |> json(%{ok: false})
    end
  end
end
