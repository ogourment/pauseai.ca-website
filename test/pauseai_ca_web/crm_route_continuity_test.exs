defmodule PauseAiCaWeb.CRMRouteContinuityTest do
  use PauseAiCaWeb.ConnCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Repo}
  alias PauseAiCaWeb.{AdminContactsLive, AssistantSettingsLive, Router}

  @protected [
    "/admin/assistant",
    "/admin/contacts",
    "/admin/contacts/legacy/11111111-1111-4111-8111-111111111111",
    "/admin/contacts/11111111-1111-4111-8111-111111111111"
  ]

  test "the protected assistant and contact routes share the management live session without losing HTTP guards" do
    for path <-
          @protected ++
            ["/manage/lists", "/manage/mail/drafts/11111111-1111-4111-8111-111111111111"] do
      info = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")
      assert {_, _, _, %{name: :require_authenticated_user}} = info.phoenix_live_view
      assert :require_authenticated_user in info.pipe_through
      if path in @protected, do: assert(:require_superadmin_user in info.pipe_through)
    end

    # Audit and unrelated administrative pages keep their existing boundary.
    for path <- ["/admin/dashboard", "/admin/assistant/activity", "/admin/contact-imports"] do
      info = Phoenix.Router.route_info(Router, "GET", path, "www.example.com")
      assert {_, _, _, %{name: :require_superadmin_user}} = info.phoenix_live_view
      assert :require_superadmin_user in info.pipe_through
    end
  end

  test "a confirmed superadmin retains initial access at both canonical workspace entries", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    authenticated = log_in_user(conn, admin)

    assert authenticated |> get("/admin/contacts?locale=en") |> html_response(200) =~
             ~s(id="crm-directory")

    assert authenticated |> get("/admin/assistant?locale=en") |> html_response(200) =~
             ~s(id="assistant-settings")
  end

  test "ordinary, unconfirmed and freshly revoked accounts receive no protected fields", %{
    conn: conn
  } do
    ordinary = user_fixture()

    unconfirmed =
      unconfirmed_user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    stale_scope = Accounts.Scope.for_user(admin)
    authenticated = log_in_user(conn, admin)
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

    for account <- [ordinary, unconfirmed], path <- @protected do
      response = conn |> recycle() |> log_in_user(account) |> get(path <> "?locale=en")
      assert response(response, 403) == "superadmin required"
    end

    for path <- @protected do
      assert authenticated |> get(path <> "?locale=en") |> response(403) == "superadmin required"
    end

    # Live navigation uses the shared authenticated session, so mount must reject
    # stale authority independently of the initial HTTP plug.
    for scope <- [Accounts.Scope.for_user(unconfirmed), stale_scope] do
      socket = %Phoenix.LiveView.Socket{
        private: %{live_temp: %{}},
        assigns: %{__changed__: %{}, flash: %{}, current_scope: scope, locale: "en"}
      }

      for view <- [AdminContactsLive, AssistantSettingsLive] do
        assert {:ok, denied} = view.mount(%{"locale" => "en"}, %{}, socket)
        assert {:redirect, %{to: destination}} = denied.redirected
        assert destination in ["/", "/dashboard"]

        for field <- [:records, :record, :form, :admins, :enabled],
            do: refute(Map.has_key?(denied.assigns, field))
      end
    end
  end
end
