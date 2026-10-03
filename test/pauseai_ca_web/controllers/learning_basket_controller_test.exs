defmodule PauseAiCaWeb.LearningBasketControllerTest do
  use PauseAiCaWeb.ConnCase, async: true
  alias PauseAiCa.{Accounts, Learning}
  import PauseAiCa.AccountsFixtures

  test "LEARN-REQ-07 anonymous writes cannot change an account", %{conn: conn} do
    conn = post(conn, "/learning/basket", %{operation: "merge", ids: Learning.ids()})
    assert json_response(conn, 401)["error"] == "authentication_required"
  end

  test "LEARN-REQ-01 account adds and removes validated nuggets while preserving other resources",
       %{conn: conn} do
    user = user_fixture()
    {:ok, user} = Accounts.save_resource(user, "risk")
    conn = log_in_user(conn, user)

    added =
      post(conn, "/learning/basket", %{
        operation: "merge",
        ids: ["bengio-speed", "invalid", "bengio-speed"]
      })

    assert json_response(added, 200)["ids"] == ["risk", "bengio-speed"]

    removed =
      added |> recycle() |> post("/learning/basket", %{operation: "remove", id: "bengio-speed"})

    assert json_response(removed, 200)["ids"] == ["risk"]
  end

  test "LEARN-REQ-07 continuation saves validated list and local context without subscribing", %{
    conn: _conn
  } do
    user = user_fixture()

    context =
      Accounts.Onboarding.context(
        %{
          "locale" => "fr",
          "basket" => "stop-button,invalid,bengio-speed",
          "fsa" => "h2x",
          "return_to" => "https://evil.example"
        },
        nil
      )

    assert context["basket"] == ["stop-button", "bengio-speed"]
    refute context["return_to"] =~ "evil"
    assert :ok = Accounts.Onboarding.apply_context(user, context, nil)
    saved = Accounts.get_user!(user.id)
    assert saved.saved_resources == ["stop-button", "bengio-speed"]
    assert saved.fsa == "H2X"
    refute saved.local_updates
  end
end
