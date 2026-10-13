defmodule PauseAiCaWeb.ParticipationLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  alias PauseAiCa.{Participation, Repo, Accounts}

  test "two entry CTAs share fields and preserve them when choosing local participation", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/en/learn")
    assert has_element?(view, "#participation-ctas button", "Get updates")
    assert has_element?(view, "#participation-ctas button", "Take action")

    view
    |> form("#participation-form",
      participation: %{name: "Morgan Example", email: "morgan@example.org", fsa: "M5V"}
    )
    |> render_change()

    view |> element("#participation-ctas button", "Take action") |> render_click()
    view |> element("#participation-motivations button", "Join the waitlist") |> render_click()
    assert has_element?(view, "input[name='participation[name]'][value='Morgan Example']")
    assert has_element?(view, "input[name='participation[email]'][value='morgan@example.org']")
    assert has_element?(view, "input[name='participation[fsa]'][value='M5V']")
    assert has_element?(view, "#participation-local")

    assert has_element?(
             view,
             "input[type=checkbox][name='participation[account]']:not([checked])"
           )
  end

  test "newsletter landing can select both companion choices and sends a single localized link",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/en/participate?intent=newsletter")

    view
    |> form("#participation-form",
      participation: %{newsletter: "true", account: "true", local: "true"}
    )
    |> render_change()

    view
    |> form("#participation-form",
      participation: %{email: "combined@example.org", name: "Morgan", fsa: "M5V", city: "Toronto"}
    )
    |> render_submit()

    assert has_element?(view, "#account-email-pending")
    assert_receive {:email, mail}
    refute_receive {:email, _}
    assert mail.subject == "Confirm your choices"
    assert mail.text_body =~ "Local waitlist: Toronto"
    assert Repo.one!(Participation.Request).state == "pending"
    refute Accounts.get_user_by_email("combined@example.org").superadmin
  end

  test "Toronto campaign starts directly on a waitlist and can switch to offering help", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/en/participate?intent=waitlist&city=Toronto")
    assert has_element?(view, "input[name='participation[city]'][value='Toronto']")
    assert has_element?(view, "#participation-submit", "Join the waitlist")
    view |> element("#participation-motivations button", "I can help") |> render_click()
    assert has_element?(view, "textarea[name='participation[help_text]']")
    assert has_element?(view, "#participation-submit", "Offer my help")
  end
end
