defmodule PauseAiCaWeb.RogueGameControllerTest do
  use PauseAiCaWeb.ConnCase, async: true
  alias PauseAiCa.{Repo, Accounts, Engagement}
  alias PauseAiCa.Engagement.GameAttempt
  import PauseAiCa.AccountsFixtures

  test "POPUP-IMPL-01 locale routes expose sourced nuggets and account-independent exit", %{
    conn: conn
  } do
    for {path, locale} <- [{"/en/rogue-agent", "en"}, {"/fr/agent-rebelle", "fr"}] do
      html = conn |> get(path) |> html_response(200)
      assert html =~ ~s(data-locale="#{locale}")
      assert html =~ "LEARN-NUGGET-DECEPTION"
      assert html =~ "arxiv.org/abs/2412.04984"
      assert html =~ ~s(id="exit")
    end
  end

  test "POPUP-METRIC-01 aggregate retries, ownership and verified-account association", %{
    conn: conn
  } do
    attrs = %{
      id: Ecto.UUID.generate(),
      locale: "en",
      sequence: 1,
      furthest_stage: 2,
      completed: false,
      buttons: %{"2:trick" => 3}
    }

    conn = post(conn, "/learning/game-progress", attrs)
    assert json_response(conn, 200)["ok"]
    visitor = Repo.get!(GameAttempt, attrs.id).visitor_id
    retry = conn |> recycle() |> post("/learning/game-progress", attrs)
    assert json_response(retry, 200)["ok"]
    assert Repo.get!(GameAttempt, attrs.id).buttons == %{"2:trick" => 3}

    done = %{
      attrs
      | sequence: 2,
        furthest_stage: 7,
        completed: true,
        buttons: %{"2:trick" => 3, "7:trick" => 1}
    }

    assert conn |> recycle() |> post("/learning/game-progress", done) |> json_response(200)
    assert conn |> recycle() |> post("/learning/game-progress", attrs) |> json_response(200)
    assert Repo.get!(GameAttempt, attrs.id).completed

    outsider =
      build_conn() |> post("/learning/game-progress", %{done | sequence: 3, buttons: %{}})

    assert json_response(outsider, 200)
    assert Repo.get!(GameAttempt, attrs.id).sequence == 2
    first = user_fixture()
    second = user_fixture()
    Engagement.associate_learning_visitor(visitor, first.id)
    Engagement.associate_learning_visitor(visitor, second.id)
    assert Repo.get!(GameAttempt, attrs.id).user_id == first.id
    assert Repo.get!(GameAttempt, attrs.id).buttons["7:trick"] == 1
  end

  test "POPUP-BOOKMARK-01 incident readings survive onboarding and are available in another session",
       %{conn: conn} do
    user = user_fixture()

    context =
      Accounts.Onboarding.context(%{"basket" => "LEARN-NUGGET-DECEPTION", "locale" => "fr"}, nil)

    assert :ok = Accounts.Onboarding.apply_context(user, context, nil)
    user = Accounts.get_user!(user.id)
    assert user.saved_resources == ["LEARN-NUGGET-DECEPTION"]
    html = conn |> log_in_user(user) |> get("/fr/agent-rebelle") |> html_response(200)
    assert html =~ ~s(data-account="[&quot;LEARN-NUGGET-DECEPTION&quot;]")

    conn =
      build_conn()
      |> log_in_user(user)
      |> post("/learning/basket", %{operation: "remove", id: "LEARN-NUGGET-DECEPTION"})

    assert json_response(conn, 200)["ids"] == []
  end

  test "POPUP-METRIC-02 rejects arbitrary properties and invalid aggregate keys", %{conn: conn} do
    attrs = %{
      id: Ecto.UUID.generate(),
      locale: "en",
      sequence: 1,
      furthest_stage: 8,
      buttons: %{"email" => "person@example.com"}
    }

    assert conn |> post("/learning/game-progress", attrs) |> json_response(422) == %{
             "ok" => false
           }
  end
end
