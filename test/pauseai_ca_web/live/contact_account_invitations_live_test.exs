defmodule PauseAiCaWeb.ContactAccountInvitationsLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Accounts}
  alias PauseAiCa.Newsletters.Draft

  test "selection survives pagination and invitation context creates a reviewable draft for exactly those contacts",
       %{conn: conn} do
    actor =
      user_fixture() |> Ecto.Changeset.change(superadmin: true, name: "Olivier") |> Repo.update!()

    people =
      for i <- 1..11 do
        person =
          Repo.insert!(%PhoenixCRM.Person{
            name: "Invitation contact #{String.pad_leading(to_string(i), 2, "0")}"
          })

        Repo.insert!(%PhoenixCRM.Address{
          person_id: person.id,
          email: "selection-#{i}@example.org"
        })

        person
      end

    flush_emails()
    users = Repo.aggregate(Accounts.User, :count)
    {:ok, view, _} = live(log_in_user(conn, actor), "/admin/contacts?locale=en&per=10")
    view |> element("button[phx-click=select-page]") |> render_click()
    assert has_element?(view, "#crm-selection-actions", "10 selected across pages")
    view |> element("#crm-pagination a", "Next") |> render_click()
    assert has_element?(view, "#crm-select-#{List.last(people).id}:not(:checked)")
    view |> element("#crm-select-#{List.last(people).id}") |> render_click()
    assert has_element?(view, "#crm-selection-actions", "11 selected across pages")
    view |> element("#crm-invite-selected") |> render_click()
    assert has_element?(view, "#crm-invitation-form")
    assert has_element?(view, "#invitation_inviter[value=Olivier]")

    view
    |> form("#crm-invitation-form",
      invitation: %{
        inviter: "Olivier",
        reason_en: "You offered to help with the Toronto incubator.",
        reason_fr: "Vous avez proposé votre aide pour l’incubateur de Toronto."
      }
    )
    |> render_submit()

    assert_redirect(view)
    [draft] = Repo.all(Draft)
    assert Enum.sort(draft.recipient_keys) == Enum.sort(Enum.map(people, & &1.id))
    assert draft.edition == "unknown"
    assert draft.source =~ "Toronto incubator"
    assert Repo.aggregate(Accounts.User, :count) == users
    refute_receive {:email, _}
  end

  test "the individual action is available in the directory and on the contact profile", %{
    conn: conn
  } do
    actor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic individual"})

    Repo.insert!(%PhoenixCRM.Address{
      person_id: person.id,
      email: "individual-invite@example.org"
    })

    conn = log_in_user(conn, actor)
    {:ok, view, _} = live(conn, "/admin/contacts?locale=en")
    assert has_element?(view, "#crm-contact-#{person.id} button[phx-click=invite-account]")
    {:ok, profile, _} = live(conn, "/admin/contacts/#{person.id}?locale=en")
    profile |> element("#crm-record button[phx-click=invite-account]") |> render_click()
    assert has_element?(profile, "#crm-invitation-form")
    assert has_element?(profile, "#crm-invitation", "For 1 selected contacts")
  end

  test "a known English invitation records the choice and requires no French text", %{conn: conn} do
    actor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(actor)

    {:ok, record} =
      PauseAiCa.CRM.create(scope, %{
        email: "english-invite@example.org",
        name: "Synthetic English"
      })

    {:ok, view, _} =
      live(log_in_user(conn, actor), "/admin/contacts/#{record.person.id}?locale=en")

    view |> element("#crm-record button[phx-click=invite-account]") |> render_click()

    view
    |> form("#crm-invitation-form",
      invitation: %{
        language: "en",
        eligible: "true",
        inviter: "Organizer",
        reason_en: "Please help with the Toronto group."
      }
    )
    |> render_change()

    refute has_element?(view, "#invitation_reason_fr")

    view
    |> form("#crm-invitation-form",
      invitation: %{
        language: "en",
        eligible: "true",
        inviter: "Organizer",
        reason_en: "Please help with the Toronto group."
      }
    )
    |> render_submit()

    {path, _} = assert_redirect(view)
    {:ok, draft_view, _} = live(log_in_user(conn, actor), path)
    assert has_element?(draft_view, "#email-send-now", "Send now")
    [draft] = Repo.all(Draft)
    assert draft.edition == "en"
    refute draft.source =~ "vous invite"

    assert [%{edition: "en"}] =
             PauseAiCa.Newsletters.Edition.decorate([%{email: "english-invite@example.org"}])

    refute_receive {:email, %{subject: "Your invitation to PauseAI Canada"}}
  end

  test "the visible review and send action delivers the frozen invitation to the local sink", %{
    conn: conn
  } do
    Swoosh.TestAssertions.set_swoosh_global()
    actor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(actor)

    {:ok, record} =
      PauseAiCa.CRM.create(scope, %{email: "send-invite@example.org", name: "Synthetic recipient"})

    {:ok, %{drafts: [draft]}} =
      PauseAiCa.Newsletters.Drafts.create_account_invitations(scope, [record.person.id], %{
        "language" => "en",
        "inviter" => "Organizer",
        "reason_en" => "Please join our local group."
      })

    {:ok, view, _} = live(log_in_user(conn, actor), "/manage/mail/drafts/#{draft.id}?locale=en")
    assert has_element?(view, "#email-review-send")

    render_submit(view, "save", %{
      "intent" => "review",
      "draft" => %{
        "subject" => draft.subject,
        "source" => draft.source,
        "edition" => "en",
        "recipient_mode" => "contacts",
        "recipient_keys" => draft.recipient_keys,
        "outreach_reviewed" => "true"
      }
    })

    assert has_element?(view, "#email-send-now", "Send now")
    [batch] = Repo.all(PauseAiCa.Newsletters.Batch)
    assert batch.state == "review"
    view |> element("#email-send-now") |> render_click()
    render_async(view)
    assert Repo.get!(PauseAiCa.Newsletters.Batch, batch.id).state == "completed"
    assert [%{state: "accepted"}] = Repo.all(PauseAiCa.Newsletters.Delivery)
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
