defmodule PauseAiCaWeb.NewsletterDraftLiveTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters, Repo}

  test "newsletter draft is editable, durable on reload, reversible and private without delivery effects",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    conn = log_in_user(conn, admin)
    scope = Accounts.Scope.for_user(admin)
    {:ok, audience, _} = live(conn, "/manage/mail/newsletters?locale=en")
    audience |> element("button", "New draft") |> render_click()
    assert {:ok, [draft]} = Newsletters.Drafts.list(scope)
    assert_redirect(audience, "/manage/mail/newsletters/#{draft.id}?locale=en")
    path = "/manage/mail/newsletters/#{draft.id}?locale=en"
    {:ok, editor, _} = live(conn, path)

    editor
    |> form("#newsletter-draft-form",
      draft: %{subject: "Montréal recap", region: "Montréal", source: "## Next steps"}
    )
    |> render_submit()

    assert has_element?(editor, "#newsletter-save-status", "Saved")
    {:ok, reloaded, _} = live(conn, path)
    assert has_element?(reloaded, "input[value='Montréal recap']")
    reloaded |> element("button", "Archive") |> render_click()
    refute has_element?(reloaded, "#newsletter-draft-form")
    reloaded |> element("button", "Restore") |> render_click()
    assert has_element?(reloaded, "input[value='Montréal recap']")
    assert Repo.aggregate(Newsletters.Subscription, :count) == 0
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

    reloaded
    |> form("#newsletter-draft-form", draft: %{subject: "revoked edit"})
    |> render_submit()

    assert_redirect(reloaded, "/dashboard")
    assert Repo.get!(Newsletters.Draft, draft.id).subject == "Montréal recap"
  end
end
