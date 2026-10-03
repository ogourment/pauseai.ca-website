defmodule PauseAiCaWeb.AdministratorsLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Volunteers, MailSafety}
  alias PauseAiCa.Accounts.Scope

  setup %{conn: conn} do
    previous = MailSafety.environment()
    on_exit(fn -> Application.put_env(:pauseai_ca, :mail_environment, previous) end)
    admin = confirmed_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    reviewer = confirmed_fixture()
    {:ok, group} = Volunteers.create_group(Scope.for_user(admin), %{name: "Montréal"})
    manager = confirmed_fixture()
    {:ok, _} = Volunteers.assign_manager(Scope.for_user(admin), group.id, manager.email)
    Application.put_env(:pauseai_ca, :mail_environment, :staging)
    %{conn: log_in_user(conn, admin), admin: admin, reviewer: reviewer, manager: manager}
  end

  test "STAGE-ACCESS-01 dedicated roster, simple whitelist, reload and no role or email side effects",
       %{conn: conn, admin: admin, reviewer: reviewer, manager: manager} do
    {:ok, view, _} = live(conn, "/manage/administrators?locale=en")
    assert has_element?(view, "#management-tabs a[aria-current=page]", "Administrators")
    assert has_element?(view, "#superadmin-list", admin.email)
    assert has_element?(view, "#group-manager-list", manager.email)
    refute has_element?(view, "#announcement-banners")

    view
    |> form("#staging-sign-in-form", access: %{email: "missing@example.org"})
    |> render_submit()

    assert has_element?(view, "#staging-sign-in-form", "Choose an existing account")
    view |> form("#staging-sign-in-form", access: %{email: reviewer.email}) |> render_submit()
    assert has_element?(view, "#staging-access-saved", "No email sent")
    refute Repo.get!(PauseAiCa.Accounts.User, reviewer.id).superadmin
    {:ok, reloaded, _} = live(conn, "/manage/administrators?locale=fr")
    assert has_element?(reloaded, "#staging-sign-in li", reviewer.email)
    reloaded |> element("button[phx-click=remove-sign-in]") |> render_click()
    refute Repo.get!(PauseAiCa.Accounts.User, reviewer.id).staging_login_allowed
    refute_receive {:email, _}
  end

  test "group managers cannot manage the whitelist and production hides it", %{
    conn: conn,
    manager: manager
  } do
    other = build_conn() |> log_in_user(manager)
    assert {:error, {:redirect, %{to: "/dashboard"}}} = live(other, "/manage/administrators")
    Application.put_env(:pauseai_ca, :mail_environment, :production)
    {:ok, view, _} = live(conn, "/manage/administrators")
    refute has_element?(view, "#staging-sign-in")
    assert has_element?(view, "#superadmin-list")
  end

  defp confirmed_fixture do
    unconfirmed_user_fixture()
    |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
    |> Repo.update!()
  end
end
