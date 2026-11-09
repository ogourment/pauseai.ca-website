defmodule PauseAiCaWeb.CampaignMenuLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Repo}
  alias PauseAiCa.Donations.Pages

  setup do
    previous = Application.get_env(:pauseai_ca, :manifund_donations_enabled)
    Application.put_env(:pauseai_ca, :manifund_donations_enabled, true)
    on_exit(fn -> Application.put_env(:pauseai_ca, :manifund_donations_enabled, previous) end)
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    {:ok, page} = Pages.get_or_create(scope)

    deadline =
      DateTime.utc_now()
      |> DateTime.add(18 * 86_400)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    payload = put_in(page.payload, ["campaign", "closes_at"], deadline)
    {:ok, page} = Pages.save(scope, page, payload)
    {:ok, _} = Pages.publish(scope, page)
    %{admin: admin}
  end

  test "anonymous and signed-in home headers show two boxes before the final seven days", %{
    admin: admin
  } do
    for user <- [nil, admin], path <- ["/en", "/fr"] do
      conn = if user, do: log_in_user(build_conn(), user), else: build_conn()
      html = conn |> get(path) |> html_response(200) |> LazyHTML.from_fragment()
      assert Enum.count(LazyHTML.query(html, "#site-header #menu-countdown:not([hidden])")) == 1

      assert Enum.count(
               LazyHTML.query(html, "#menu-countdown [data-countdown-part]:not([hidden])")
             ) ==
               2
    end
  end

  test "the donation page uses its full timer and omits the menu timer", %{admin: admin} do
    for user <- [nil, admin], path <- ["/en/donate", "/fr/faire-un-don"] do
      conn = if user, do: log_in_user(build_conn(), user), else: build_conn()
      {:ok, view, _} = live(conn, path)
      refute has_element?(view, "#menu-countdown")
      assert has_element?(view, "#donation-countdown")
    end
  end

  test "management headers keep the counter without adding promotional banners", %{admin: admin} do
    {:ok, view, _} = live(log_in_user(build_conn(), admin), "/admin/contacts?locale=en")
    assert has_element?(view, "#site-header #menu-countdown:not([hidden])")
    refute has_element?(view, "#announcement-banners")
  end
end
