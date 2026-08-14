defmodule PauseAiCaWeb.LearningSignalControllerTest do
  use PauseAiCaWeb.ConnCase, async: true

  alias PauseAiCa.Engagement.LearningSignal
  alias PauseAiCa.Repo

  test "an anonymous homepage answer becomes a durable learning signal", %{conn: conn} do
    conn = post(conn, ~p"/learning/questions/risk", %{answer: "4", complete: false})

    assert json_response(conn, 200) == %{"ok" => true}

    assert %{kind: "question_answered", subject: "risk", value: "4", user_id: nil} =
             Repo.one!(LearningSignal)
  end

  test "completing the homepage questions records completion without duplicating a person", %{
    conn: conn
  } do
    post(conn, ~p"/learning/questions/coordination", %{answer: "3", complete: true})

    assert Repo.aggregate(LearningSignal, :count) == 2
    assert Repo.get_by!(LearningSignal, kind: "questionnaire_completed")
  end

  test "opening Learn counts an anonymous browser once", %{conn: conn} do
    conn = get(conn, ~p"/en/learn")
    assert Repo.get_by!(LearningSignal, kind: "learn_page_visited")

    conn |> recycle() |> get(~p"/en/learn")
    assert Repo.aggregate(LearningSignal, :count) == 1
  end

  test "opening a reviewed resource records the signal and redirects", %{conn: conn} do
    conn = get(conn, ~p"/learning/resources/pauseai-learn")

    assert redirected_to(conn) == "https://pauseai.info/learn"
    assert Repo.get_by!(LearningSignal, kind: "resource_opened", subject: "pauseai-learn")
  end
end
