defmodule PauseAiCaWeb.Plugs.LearningIdentity do
  @moduledoc "Assigns a random first-party browser identity and links it to an account after sign-in."

  import Plug.Conn

  alias PauseAiCa.Engagement

  @session_key :learning_visitor_id

  def init(opts), do: opts

  def call(conn, _opts) do
    visitor_id = get_session(conn, @session_key) || Ecto.UUID.generate()
    user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    if user, do: Engagement.associate_learning_visitor(visitor_id, user.id)

    conn
    |> put_session(@session_key, visitor_id)
    |> assign(:learning_visitor_id, visitor_id)
  end
end
