defmodule PauseAiCaWeb.ContactMpLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  alias PauseAiCa.{Accounts, Participation, Repo}

  test "direct bilingual entry invites account/newsletter immediately without requiring either",
       %{conn: conn} do
    for {path, heading, alternate} <- [
          {"/en/contact-your-mp", "Email your MP", "/fr/contacter-votre-depute"},
          {"/fr/contacter-votre-depute", "Écrire à votre député·e", "/en/contact-your-mp"}
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "h1", heading)
      assert has_element?(view, "a[href='#{alternate}']")
      assert has_element?(view, "#act-contact-mp")
      assert has_element?(view, "input[name='participation[postal_code]']")

      assert has_element?(
               view,
               "input[type=checkbox][name='participation[account]'][checked]"
             )

      assert has_element?(
               view,
               "input[type=checkbox][name='participation[newsletter]'][checked]"
             )

      refute has_element?(view, "#warning-shot-page-badge")
      refute has_element?(view, "#developments")
      refute has_element?(view, "#participation-motivations")
    end
  end

  test "MP choices remain unchecked after validation and rerender when the visitor opts out", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/en/contact-your-mp")

    view
    |> form("#participation-form",
      participation: %{
        account: "false",
        newsletter: "false",
        email: "optout@example.org",
        postal_code: "H2X"
      }
    )
    |> render_change()

    view |> form("#participation-form") |> render_submit()
    assert has_element?(view, "#participation-validation")
    view |> form("#participation-form", participation: %{name: "Morgan"}) |> render_change()

    assert has_element?(
             view,
             "input[type=checkbox][name='participation[account]']:not([checked])"
           )

    assert has_element?(
             view,
             "input[type=checkbox][name='participation[newsletter]']:not([checked])"
           )

    refute Repo.exists?(Participation.Request)
    refute_receive {:email, _}
  end

  test "one set of details prepares a letter with no account/subscription side effect", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/en/contact-your-mp")

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan Example",
        email: "mp-only@example.org",
        account: "false",
        newsletter: "false",
        postal_code: "H2X 1Y4"
      }
    )
    |> render_submit()

    assert has_element?(view, "#mp-results", "Steven Guilbeault")
    assert has_element?(view, "#letter-form")

    assert has_element?(
             view,
             "#send-form input[type=hidden][name='send[email]'][value='mp-only@example.org']"
           )

    refute has_element?(view, "#send-form input[type=email]")
    refute Repo.exists?(Participation.Request)
    refute Accounts.get_user_by_email("mp-only@example.org")
    refute_receive {:email, _}
    view |> form("#send-form", send: %{consent: "true"}) |> render_submit()
    assert has_element?(view, "#awaiting-confirmation")
    assert_receive {:email, mail}
    assert mail.to == [{"", "mp-only@example.org"}]
    assert mail.subject =~ "Confirm and send your letter"
    refute_receive {:email, _}
  end

  test "explicit companion choices use the existing confirmation with derived FSA", %{conn: conn} do
    {:ok, view, _} = live(conn, "/en/contact-your-mp")

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan Example",
        email: "mp-choices@example.org",
        postal_code: "h2x 1y4"
      }
    )
    |> render_submit()

    assert has_element?(view, "#letter-form")
    assert has_element?(view, "#account-email-pending")
    request = Repo.one!(Participation.Request)
    assert request.fsa == "H2X"
    assert request.account && request.newsletter
    assert request.state == "pending"
    assert request.context["source"] == "contact_mp"
    assert_receive {:email, mail}
    assert mail.subject == "Confirm your choices"
    assert mail.to == [{"", "mp-choices@example.org"}]
    refute_receive {:email, _}
  end

  test "invalid or incomplete postal code stays on the shared form without sending", %{conn: conn} do
    {:ok, view, _} = live(conn, "/en/contact-your-mp")

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan",
        email: "invalid-mp@example.org",
        postal_code: "H2X",
        account: "true"
      }
    )
    |> render_submit()

    assert has_element?(view, "#participation-validation")
    assert has_element?(view, "#participation-form", "enter a full Canadian postal code")
    refute has_element?(view, "#letter-form")
    refute Repo.exists?(Participation.Request)
    refute_receive {:email, _}
  end

  test "changing companion choices preserves an already edited letter", %{conn: conn} do
    {:ok, view, _} = live(conn, "/en/contact-your-mp")

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan",
        email: "mp-edit@example.org",
        postal_code: "H2X 1Y4",
        account: "false",
        newsletter: "false"
      }
    )
    |> render_submit()

    view
    |> form("#letter-form", letter: %{subject: "My subject", body: "My personal message."})
    |> render_change()

    view |> form("#participation-form", participation: %{newsletter: "true"}) |> render_submit()
    assert has_element?(view, "#letter-form input[value='My subject']")
    assert has_element?(view, "#letter-form textarea", "My personal message.")
    assert Repo.one!(Participation.Request).newsletter
    refute Repo.one!(Participation.Request).account
    refute Accounts.get_user_by_email("mp-edit@example.org")
  end

  test "a signed-in visitor cannot replace the account identity through submitted fields", %{
    conn: conn
  } do
    user = PauseAiCa.AccountsFixtures.user_fixture()
    {:ok, view, _} = live(log_in_user(conn, user), "/en/contact-your-mp")

    view
    |> form("#participation-form",
      participation: %{
        name: "Morgan",
        email: "wrong-identity@example.org",
        postal_code: "H2X 1Y4",
        newsletter: "true"
      }
    )
    |> render_submit()

    assert has_element?(view, "#send-form input[name='send[email]'][value='#{user.email}']")
    assert Repo.one!(Participation.Request).email == user.email
    refute Accounts.get_user_by_email("wrong-identity@example.org")
  end

  test "French inline errors remain visible after initially unused fields are filled", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/fr/contacter-votre-depute")

    view
    |> form("#participation-form")
    |> render_change(%{"participation" => %{"_unused_postal_code" => "", "name" => "Camille"}})

    view
    |> form("#participation-form",
      participation: %{email: "fr-error@example.org", postal_code: "H2X"}
    )
    |> render_submit()

    assert has_element?(view, "#participation-form", "saisissez un code postal canadien complet")
    refute has_element?(view, "#letter-form")
  end
end
