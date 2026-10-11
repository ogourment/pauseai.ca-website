defmodule PauseAiCaWeb.NewsletterListsLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters, Repo}
  alias PauseAiCa.Newsletters.{Lists, Drafts}

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{conn: log_in_user(conn, admin), scope: Accounts.Scope.for_user(admin)}
  end

  test "an administrator creates dynamic rules, reloads and previews actual membership", c do
    {:ok, request} =
      Newsletters.request_signup("rules@example.org", %{consent: true, city: "Laval", fsa: "H2X"})

    {:ok, _} = Newsletters.confirm(request.confirmation_token)
    {:ok, view, _} = live(c.conn, "/manage/mail/newsletters?locale=en")
    view |> element("button[phx-value-preset=montreal]") |> render_click()
    assert has_element?(view, "#list_name[value='Montréal']")

    view
    |> form("#mailing-list-form",
      list: %{name: "Montréal area", match: "any", city: "Montréal", region: "", fsas: "H2X"}
    )
    |> render_submit()

    {:ok, [list]} = Lists.list(c.scope)
    {:ok, reloaded, _} = live(c.conn, "/manage/mail/newsletters?locale=en&list_id=#{list.id}")
    assert has_element?(reloaded, "#mailing-list-#{list.id}", "Montréal area")
    assert render(reloaded) =~ "rules@example.org"
    assert render(reloaded) =~ "Matches: FSA"
    reloaded |> element("#mailing-list-#{list.id} button[phx-click=list-edit]") |> render_click()

    reloaded
    |> form("#mailing-list-form",
      list: %{name: "Montréal area", match: "all", city: "Montréal", region: "", fsas: "H2X"}
    )
    |> render_submit()

    {:ok, _, html} = live(c.conn, "/manage/mail/newsletters?locale=en&list_id=#{list.id}")
    refute html =~ "rules@example.org"
  end

  test "composer chooses a whole dynamic list, persists it and hides individual selection", c do
    {:ok, list} =
      Lists.save(c.scope, nil, %{"name" => "Montréal", "city" => "Montréal", "match" => "any"})

    {:ok, draft} = Drafts.create_for_list(c.scope, list.id)
    {:ok, view, _} = live(c.conn, "/manage/mail/drafts/#{draft.id}?locale=en")
    view |> form("#newsletter-draft-form", draft: %{recipient_mode: "list"}) |> render_change()
    assert has_element?(view, "#draft_mailing_list_id")
    refute has_element?(view, "button[phx-click=select-visible]")

    view
    |> form("#newsletter-draft-form",
      draft: %{
        recipient_mode: "list",
        mailing_list_id: list.id,
        subject: "Local newsletter",
        source: "News"
      }
    )
    |> render_submit()

    {:ok, saved} = Drafts.get(c.scope, draft.id)
    assert saved.mailing_list_id == list.id
    {:ok, reloaded, _} = live(c.conn, "/manage/mail/drafts/#{draft.id}?locale=en")
    assert has_element?(reloaded, "#draft_mailing_list_id option[value='#{list.id}'][selected]")
    assert has_element?(reloaded, "#whole-list-audience", "Eligible: 0")
  end
end
