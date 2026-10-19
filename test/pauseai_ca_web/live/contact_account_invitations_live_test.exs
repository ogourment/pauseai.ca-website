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

    assert has_element?(view, "#crm-invitation-drafts a", "Your invitation")
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

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
