defmodule PauseAiCaWeb.EmailPreferencesLiveTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, CRM, Newsletters, Repo}

  test "manual request is available off the list page and persists", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    conn = log_in_user(conn, admin)
    {:ok, list, _} = live(conn, "/manage/mail/newsletters?locale=en")
    refute has_element?(list, "#newsletter-withdrawal")
    assert has_element?(list, "#mail-more a[href='/manage/mail/preferences?locale=en']")
    {:ok, view, _} = live(conn, "/manage/mail/preferences?locale=en")

    view
    |> form("#newsletter-withdrawal",
      withdrawal: %{email: "absent@example.org", reason: "Email request"}
    )
    |> render_submit()

    assert has_element?(view, "#withdrawal-result", "absent@example.org")
    refute Newsletters.outreach_eligible?("absent@example.org")
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

    view
    |> form("#newsletter-withdrawal",
      withdrawal: %{email: "denied@example.org", reason: "Email request"}
    )
    |> render_submit()

    refute Repo.get_by(Newsletters.Subscription, email: "denied@example.org")
  end

  test "contact choices cover two addresses atomically and reject unrelated addresses", %{
    conn: conn
  } do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)

    {:ok, record} =
      CRM.create(scope, %{"name" => "Synthetic person", "email" => "one@example.org"})

    Repo.insert!(%PhoenixCRM.Address{person_id: record.person.id, email: "two@example.org"})

    {:ok, view, _} =
      live(
        log_in_user(conn, admin),
        "/manage/mail/preferences?contact_id=#{record.person.id}&locale=en"
      )

    assert has_element?(view, "input[value='one@example.org']")
    assert has_element?(view, "input[value='two@example.org']")

    render_submit(view, "record-withdrawal", %{
      "withdrawal" => %{
        "emails" => ["one@example.org", "unrelated@example.org"],
        "reason" => "Request"
      }
    })

    refute Repo.get_by(Newsletters.Subscription, email: "one@example.org")

    render_submit(view, "record-withdrawal", %{
      "withdrawal" => %{
        "emails" => ["one@example.org", "two@example.org"],
        "reason" => "Request for both"
      }
    })

    assert has_element?(view, "#withdrawal-result", "two@example.org")

    for email <- ["one@example.org", "two@example.org"],
        do: refute(Newsletters.outreach_eligible?(email))

    {:ok, reloaded, _} =
      live(
        log_in_user(conn, admin),
        "/manage/mail/preferences?contact_id=#{record.person.id}&locale=en"
      )

    assert render(reloaded) =~ "Withdrawn"
  end

  test "subscriber shortcut and unprivileged access", %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    {:ok, signup} = Newsletters.request_signup("subscriber@example.org", %{consent: true})
    {:ok, list, _} = live(log_in_user(conn, admin), "/manage/mail/newsletters?locale=en")

    assert has_element?(
             list,
             "a[href='/manage/mail/preferences?locale=en&subscription_id=#{signup.subscription.id}']",
             "Unsubscribe"
           )

    {:ok, page, _} =
      live(
        log_in_user(conn, admin),
        "/manage/mail/preferences?subscription_id=#{signup.subscription.id}&locale=en"
      )

    assert has_element?(page, "input[value='subscriber@example.org']")

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             live(log_in_user(conn, user_fixture()), "/manage/mail/preferences?locale=en")
  end
end
