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

  test "donation interest counts each browser once, without recording payment details", %{
    conn: conn
  } do
    path = ~p"/engagement/donation-links/manifund"
    conn = post(conn, path, %{amount: "100", email: "ignored@example.org"})
    assert response(conn, 204)
    assert conn |> recycle() |> post(path) |> response(204)

    assert [%{kind: "donation_link_opened", subject: "manifund", value: nil, user_id: nil}] =
             Repo.all(LearningSignal)

    assert build_conn() |> post(path) |> response(204)
    assert Repo.aggregate(LearningSignal, :count) == 2
  end

  test "unknown donation destinations cannot create signals", %{conn: conn} do
    assert conn |> post(~p"/engagement/donation-links/unknown") |> response(422)
    refute Repo.one(LearningSignal)
  end

  test "donation signal requires browser CSRF protection", %{conn: conn} do
    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      conn
      |> put_private(:plug_skip_csrf_protection, false)
      |> post(~p"/engagement/donation-links/manifund")
    end

    refute Repo.one(LearningSignal)
  end

  test "brochure interest deduplicates browsers separately from Manifund", %{conn: conn} do
    path = ~p"/engagement/donation-links/brochure"
    conn = post(conn, path, %{email: "ignored@example.org", amount: "100"})
    assert response(conn, 204)
    assert conn |> recycle() |> post(path) |> response(204)
    assert conn |> recycle() |> post(~p"/engagement/donation-links/manifund") |> response(204)

    assert %{kind: "brochure_opened", subject: "brochure", value: nil, user_id: nil} =
             Repo.get_by!(LearningSignal, kind: "brochure_opened")

    assert Repo.aggregate(LearningSignal, :count) == 2
    assert build_conn() |> post(path) |> response(204)
    assert Repo.aggregate(LearningSignal, :count) == 3
  end
end
