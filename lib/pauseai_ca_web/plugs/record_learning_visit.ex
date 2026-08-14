defmodule PauseAiCaWeb.Plugs.RecordLearningVisit do
  @moduledoc "Records the first visit to the public learning library for each browser."

  alias PauseAiCa.Engagement

  @paths ["/en/learn", "/fr/comprendre", "/fr/learn"]

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET", request_path: path} = conn, _opts) when path in @paths do
    user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    Engagement.record_learning_signal(
      conn.assigns.learning_visitor_id,
      user,
      "learn_page_visited"
    )

    conn
  end

  def call(conn, _opts), do: conn
end
