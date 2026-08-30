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

  test "opening the Montréal event link counts an anonymous browser once", %{conn: conn} do
    path = ~p"/engagement/event-links/montreal-protest-2026-09-26"

    conn = post(conn, path)
    assert response(conn, 204)
    assert conn |> recycle() |> post(path) |> response(204)

    assert Repo.aggregate(LearningSignal, :count) == 1

    assert Repo.get_by!(LearningSignal,
             kind: "event_link_opened",
             subject: "montreal-protest-2026-09-26"
           )
  end

  test "unknown event links are not recorded", %{conn: conn} do
    assert conn |> post(~p"/engagement/event-links/unknown-event") |> response(422)
    refute Repo.one(LearningSignal)
  end
end
