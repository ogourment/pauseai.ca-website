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
    refute has_element?(view, "#list_match")
    assert has_element?(view, "#list_name[value='Montréal']")

    view
    |> form("#mailing-list-form",
      list: %{name: "Montréal area", city: "Montréal", region: "", fsas: "H2X"}
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
      list: %{name: "Montréal area", city: "Montréal", region: "", fsas: "J4B"}
    )
    |> render_submit()

    {:ok, _, html} = live(c.conn, "/manage/mail/newsletters?locale=en&list_id=#{list.id}")
    refute html =~ "rules@example.org"
  end

  test "area rules have a reloadable view and show stored FSA values while allowing a new custom area",
       c do
    {:ok, list} =
      Lists.save(c.scope, nil, %{
        "name" => "Ottawa volunteers",
        "city" => "Ottawa",
        "region" => "Eastern Ontario",
        "fsas" => "K1A"
      })

    {:ok, view, _} =
      live(c.conn, "/manage/mail/newsletters?locale=en&list_id=#{list.id}&view=rules")

    assert has_element?(view, "#list_fsas[value='K1A']")
    assert has_element?(view, "#list_region[value='Eastern Ontario']")
    assert has_element?(view, "[data-area-summary]", "K1A")
    refute has_element?(view, "#newsletter-audience")
    view |> element("button", "New list") |> render_click()
    assert has_element?(view, "#list_name[value='']")

    view
    |> form("#mailing-list-form",
      list: %{name: "New area", city: "Kingston", region: "", fsas: "K7L"}
    )
    |> render_submit()

    {:ok, lists} = Lists.list(c.scope)
    assert Enum.any?(lists, &(&1.name == "New area"))
    {:ok, unchanged} = Lists.get(c.scope, list.id)
    assert Lists.form(unchanged)["fsas"] == "K1A"
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
