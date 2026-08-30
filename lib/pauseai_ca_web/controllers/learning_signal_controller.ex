defmodule PauseAiCaWeb.LearningSignalController do
  use PauseAiCaWeb, :controller

  alias PauseAiCa.Engagement

  @questions ~w(risk pause coordination)
  @answers ~w(0 1 2 3 4 5)

  def question(conn, %{"question" => question, "answer" => answer} = params)
      when question in @questions and answer in @answers do
    user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    Engagement.record_learning_signal(
      conn.assigns.learning_visitor_id,
      user,
      "question_answered",
      question,
      answer
    )

    if params["complete"] in [true, "true"] do
      Engagement.record_learning_signal(
        conn.assigns.learning_visitor_id,
        user,
        "questionnaire_completed"
      )
    end

    json(conn, %{ok: true})
  end

  def question(conn, _params), do: conn |> put_status(:unprocessable_entity) |> json(%{ok: false})

  def event_link(conn, %{"event" => "montreal-protest-2026-09-26" = event}) do
    user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    Engagement.record_learning_signal(
      conn.assigns.learning_visitor_id,
      user,
      "event_link_opened",
      event
    )

    send_resp(conn, :no_content, "")
  end

  def event_link(conn, _params), do: send_resp(conn, :unprocessable_entity, "")
end
