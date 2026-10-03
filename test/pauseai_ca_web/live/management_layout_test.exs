defmodule PauseAiCaWeb.ManagementLayoutTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Mail}
  alias PauseAiCa.Accounts.Scope

  test "STAGE-UI-01 management tasks have no promotional banners or campaign prompt", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    conn = log_in_user(conn, admin)
    {:ok, batch} = Mail.create(Scope.for_user(admin), admin.id)

    paths = [
      "/admin/dashboard",
      "/admin/contact-imports",
      "/admin/contacts",
      "/admin/donation-pledges",
      "/manage/accounts",
      "/manage/accounts/new",
      "/manage/accounts/import",
      "/manage/accounts/#{admin.id}",
      "/manage/accounts/#{admin.id}/compose",
      "/manage/mail",
      "/manage/mail/#{batch.id}"
    ]

    for path <- paths, locale <- ["en", "fr"] do
      {:ok, view, _} = live(conn, path <> "?locale=" <> locale)
      assert has_element?(view, "header nav")
      assert has_element?(view, "main")
      refute has_element?(view, "#announcement-banners"), path
      refute has_element?(view, "#campaign-prompt"), path
    end
  end

  test "public pages keep their campaign announcements", %{conn: conn} do
    for path <- ["/en/learn", "/fr/comprendre"] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#montreal-protest-banner")
      assert has_element?(view, "#warning-shot-banner")
    end
  end
end
