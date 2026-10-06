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

  test "manual fourteen-contact selection survives save/reload and requires review then approval before sending",
       %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    {:ok, draft} = Newsletters.Drafts.create(scope)

    {:ok, draft} =
      Newsletters.Drafts.save(scope, draft, %{
        "subject" => "Synthetic press release",
        "source" => "# Montréal"
      })

    keys =
      for i <- 1..14 do
        person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic press contact #{i}"})
        Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: "human-#{i}@example.org"})
        person.id
      end

    conn = log_in_user(conn, admin)
    path = "/manage/mail/newsletters/#{draft.id}?locale=en"
    {:ok, view, _} = live(conn, path)

    view
    |> form("#newsletter-draft-form", draft: %{recipient_mode: "contacts"})
    |> render_change()

    for key <- keys, do: assert(has_element?(view, "input[type=checkbox][value='#{key}']"))

    view
    |> form("#newsletter-draft-form", draft: %{recipient_mode: "contacts", recipient_keys: keys})
    |> render_submit()

    assert has_element?(view, "#newsletter-selected-count", "14 selected")
    {:ok, reloaded, _} = live(conn, path)

    for key <- keys,
        do: assert(has_element?(reloaded, "input[type=checkbox][value='#{key}'][checked]"))

    reloaded |> form("#newsletter-prepare-form", review: %{eligible: "false"}) |> render_submit()
    assert has_element?(reloaded, "#newsletter-draft-error", "reviewed outreach eligibility")
    assert Repo.aggregate(Newsletters.Batch, :count) == 0
    reloaded |> form("#newsletter-prepare-form", review: %{eligible: "true"}) |> render_submit()
    assert has_element?(reloaded, "#newsletter-batch-review", "Frozen batch snapshot")
    refute has_element?(reloaded, "button[phx-click=send-batch]")
    reloaded |> element("button", "Approve batch") |> render_click()
    assert has_element?(reloaded, "button[phx-click=send-batch]", "Send")
    [batch] = Repo.all(Newsletters.Batch)
    assert batch.state == "approved"
    assert Repo.aggregate(Newsletters.Delivery, :count) == 14
    assert Enum.all?(Repo.all(Newsletters.Delivery), &(&1.state == "pending"))
    assert {:ok, saved} = Newsletters.Drafts.get(scope, draft.id)
    assert Enum.sort(saved.recipient_keys) == Enum.sort(keys)
    assert saved.recipient_mode == "contacts"
  end
end
