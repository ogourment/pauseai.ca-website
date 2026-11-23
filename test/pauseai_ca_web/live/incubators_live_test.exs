defmodule PauseAiCaWeb.IncubatorsLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Incubators, Repo, Volunteers}
  alias PauseAiCa.Accounts.Scope

  setup context do
    admin =
      user_fixture()
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()
      |> Scope.for_user()

    manager = user_fixture()
    member = user_fixture() |> Ecto.Changeset.change(name: "Review member") |> Repo.update!()

    if context[:empty_groups] do
      %{admin: admin}
    else
      {:ok, group} = Volunteers.create_group(admin, %{name: "Review incubator"})
      {:ok, grant} = Volunteers.assign_manager(admin, group.id, manager.email)

      {:ok, profile} =
        Incubators.configure(admin, group.id, %{
          "name_en" => "Review local group",
          "name_fr" => "Groupe local de démonstration",
          "area_served" => "local",
          "published" => true,
          "fsas" => "H2X",
          "whatsapp_enabled" => true,
          "whatsapp_approval_confirmed" => true,
          "moderator_contact" => "manager@example.org",
          "whatsapp_invite_url" => "https://chat.whatsapp.com/private-review-only"
        })

      %{
        admin: admin,
        manager: manager,
        member: member,
        group: group,
        grant: grant,
        profile: profile
      }
    end
  end

  @tag :empty_groups
  test "visitors see Montréal, Toronto with a march photo, then Ottawa in both editions", c do
    for city <- ["Ottawa", "Toronto", "Montréal"] do
      {:ok, group} = Volunteers.create_group(c.admin, %{name: city})

      {:ok, _} =
        Incubators.configure(c.admin, group.id, %{
          "name_en" => city,
          "name_fr" => city,
          "area_served" => "local",
          "published" => true,
          "fsas" => "H2X"
        })
    end

    for path <- ["/en/groups", "/fr/groupes"] do
      {:ok, view, _} = live(build_conn(), path)
      assert has_element?(view, ".chapter-card:nth-child(1) h2", "Montréal")
      assert has_element?(view, ".chapter-card:nth-child(2) h2", "Toronto")
      assert has_element?(view, ".chapter-card:nth-child(2) img[src$='/t-treaty.jpg']")
      assert has_element?(view, ".chapter-card:nth-child(3) h2", "Ottawa")
    end
  end

  test "Manage remembers each organizer’s last visit and scopes new activity to their groups",
       c do
    conn = log_in_user(build_conn(), c.manager)
    {:ok, first, _} = live(conn, "/manage")
    assert has_element?(first, "#group-snapshot", "Your next visit")
    {:ok, other} = Volunteers.create_group(c.admin, %{name: "Other group"})

    for group <- [c.group, other] do
      Repo.insert!(%Incubators.Event{
        group_id: group.id,
        actor_id: c.admin.user.id,
        action: "configure"
      })
    end

    {:ok, second, _} = live(conn, "/manage")
    assert has_element?(second, "#group-snapshot", "1 group activity entry")
    assert has_element?(second, "#group-snapshot a", c.group.name)
    refute has_element?(second, "#group-snapshot", other.name)
    {:ok, third, _} = live(conn, "/manage")
    assert has_element?(third, "#group-snapshot", "0 group activity entries")
  end

  test "group history stays off the members page and pages through older records", c do
    for _ <- 1..15 do
      Repo.insert!(%Incubators.Event{
        group_id: c.group.id,
        actor_id: c.manager.id,
        action: "configured"
      })
    end

    path = "/manage/groups?group=#{c.group.id}&locale=en"
    {:ok, view, _} = live(log_in_user(build_conn(), c.manager), path)
    refute has_element?(view, "#incubator-activity")
    view |> element("nav a", "Activity") |> render_click()
    first = view |> element("#incubator-activity ul") |> render()
    assert has_element?(view, "#incubator-activity li:nth-child(10)")
    refute has_element?(view, "#incubator-activity li:nth-child(11)")
    view |> element("#incubator-activity a", "Next") |> render_click()
    assert has_element?(view, "#incubator-activity a", "Previous")
    refute has_element?(view, "#incubator-activity a", "Next")
    view |> element("#incubator-activity a", "Previous") |> render_click()

    assert first == view |> element("#incubator-activity ul") |> render()
  end

  test "group activity identifies the affected member separately from the organizer", c do
    {:ok, group} = Volunteers.create_group(c.admin, %{name: "Group activity review"})
    {:ok, _} = Volunteers.assign_manager(c.admin, group.id, c.manager.email)
    {:ok, member} = Incubators.add_existing_member(c.admin, group.id, c.member.email, "member")
    event = Repo.get_by!(Incubators.Event, membership_id: member.id, action: "member_added")

    older =
      Repo.insert!(%Incubators.Event{group_id: group.id, actor_id: c.manager.id, action: "admit"})

    {:ok, view, _} =
      live(
        log_in_user(build_conn(), c.manager),
        "/manage/groups?group=#{group.id}&tab=activity&locale=en"
      )

    assert has_element?(view, "#group-event-#{older.id}", "Unknown member")
    assert has_element?(view, "#group-event-#{event.id}", "Member: Review member")
    assert has_element?(view, "#group-event-#{event.id}", "Recorded by #{c.admin.user.email}")
  end

  test "directory shortcuts and the Toronto chapter shortcut preserve the query", %{conn: conn} do
    for {short, canonical} <- [
          {"/groups", "/en/groups"},
          {"/groupes", "/fr/groupes"}
        ] do
      assert redirected_to(get(conn, short <> "?from=event"), 301) == canonical <> "?from=event"
    end

    assert redirected_to(get(conn, "/toronto?from=event"), 301) ==
             "/groups/toronto?from=event&locale=en"

    assert redirected_to(get(conn, "/toronto?locale=fr"), 301) ==
             "/groups/toronto?locale=fr"
  end

  test "CHAPTER-PUBLISH-01 scoped draft, preview, publication and revocation", c do
    {:ok, view, _} =
      live(log_in_user(build_conn(), c.manager), "/manage/groups/#{c.group.id}/homepage")

    fields = %{chapter: %{slug: "toronto", en: "First welcome", fr: "Bienvenue"}}
    view |> form("#chapter-form", fields) |> render_submit()
    assert has_element?(view, "#chapter-editor-en [data-pme-preview]")
    refute has_element?(view, "#chapter-preview")
    assert_raise Ecto.NoResultsError, fn -> live(build_conn(), "/groups/toronto") end
    view |> element("#chapter-publish") |> render_click()
    {:ok, _, public} = live(build_conn(), "/groups/toronto")
    assert public =~ "First welcome"

    for {route, locale, text} <- [
          {"/toronto", "en", "First welcome"},
          {"/toronto?locale=fr", "fr", "Bienvenue"}
        ] do
      alias_conn = build_conn() |> Plug.Test.init_test_session(%{site_locale: "fr"}) |> get(route)

      published_page =
        alias_conn
        |> recycle()
        |> get(redirected_to(alias_conn, 301))
        |> html_response(200)

      html = LazyHTML.from_document(published_page)
      assert Enum.count(LazyHTML.query(html, ~s(html[lang="#{locale}"]))) == 1

      assert published_page =~ text
    end

    view
    |> form("#chapter-form", put_in(fields, [:chapter, :en], "Private revision"))
    |> render_submit()

    {:ok, _, still_public} = live(build_conn(), "/groups/toronto")
    refute still_public =~ "Private revision"
    {:ok, second} = Volunteers.create_group(c.admin, %{name: "Other chapter"})

    assert {:error, {:redirect, _}} =
             live(log_in_user(build_conn(), c.manager), "/manage/groups/#{second.id}/homepage")

    {:ok, _} =
      Incubators.configure(c.admin, second.id, %{
        "name_en" => "Ottawa",
        "name_fr" => "Ottawa",
        "area_served" => "local",
        "fsas" => "H2X",
        "published" => true
      })

    {:ok, second_editor, _} =
      live(log_in_user(build_conn(), c.admin.user), "/manage/groups/#{second.id}/homepage")

    second_editor
    |> form("#chapter-form",
      chapter: %{slug: "ottawa", en: "Ottawa welcome", fr: "Accueil Ottawa"}
    )
    |> render_submit()

    second_editor |> element("#chapter-publish") |> render_click()
    {:ok, _, french} = live(build_conn(), "/groups/ottawa?locale=fr")
    assert french =~ "Accueil Ottawa"
    refute french =~ "First welcome"
    Volunteers.revoke_manager(c.admin, c.grant.id)
    view |> element("#chapter-publish") |> render_click()
    {:ok, _, after_revoke} = live(build_conn(), "/groups/toronto")
    assert after_revoke =~ "First welcome"
    refute after_revoke =~ "Private revision"
  end

  test "a group manager adds, edits and ends a responsibility on the group screen", c do
    member =
      Repo.insert!(%Incubators.Membership{
        group_id: c.group.id,
        user_id: c.member.id,
        display_name: "Review member",
        conduct_at: DateTime.utc_now(),
        status: "approved"
      })

    {:ok, view, _} =
      live(log_in_user(build_conn(), c.manager), "/manage/groups?group=#{c.group.id}&locale=en")

    view |> element("#group-responsibilities button", "Add responsibility") |> render_click()

    view
    |> form("#group-responsibility-form",
      responsibility: %{
        member: "#{member.id}:#{member.revision}",
        title: "Video Editor",
        starts_on: "2026-11-19"
      }
    )
    |> render_submit()

    assert has_element?(view, "#group-responsibilities li", "Video Editor")
    view |> element("#group-responsibilities li button", "Edit") |> render_click()

    view
    |> form("#group-responsibility-form",
      responsibility: %{title: "Video Lead", starts_on: "2026-11-19"}
    )
    |> render_submit()

    assert has_element?(view, "#group-responsibilities li", "Video Lead")
    view |> element("#group-responsibilities li button", "End responsibility") |> render_click()

    view
    |> form("#group-responsibility-form", responsibility: %{ends_on: "2026-11-20"})
    |> render_submit()

    assert has_element?(view, "#group-responsibilities li time[datetime='2026-11-20']")
    refute has_element?(view, "#group-responsibilities li button", "End responsibility")
  end

  @tag :empty_groups
  test "opening the event editor preserves an unconfigured group's complete draft", c do
    {:ok, group} = Volunteers.create_group(c.admin, %{name: "Unconfigured group"})
    path = "/manage/groups?group=#{group.id}&locale=en"
    assert {:ok, nil} = Incubators.configuration(c.admin, group.id)
    {:ok, view, _} = live(log_in_user(build_conn(), c.admin.user), path)

    attrs = %{
      name_en: "New local group",
      name_fr: "Nouveau groupe local",
      summary_en: "Unsaved English description",
      summary_fr: "Description française non enregistrée",
      stage: "incubator",
      events_url: "https://example.org/new-group-events"
    }

    view |> form("#incubator-config", profile: attrs) |> render_change()
    view |> element("#incubator-next-event summary") |> render_click()
    assert_patch(view, path <> "&section=next-event")
    assert has_element?(view, "#incubator-next-event[open]")
    assert has_element?(view, "input[name='profile[name_en]'][value='New local group']")
    assert has_element?(view, "input[name='profile[name_fr]'][value='Nouveau groupe local']")
    assert has_element?(view, "textarea[name='profile[summary_en]']", attrs.summary_en)
    assert has_element?(view, "textarea[name='profile[summary_fr]']", attrs.summary_fr)
    assert has_element?(view, "select[name='profile[stage]'] option[value='incubator'][selected]")

    assert has_element?(
             view,
             "input[name='profile[events_url]'][value='https://example.org/new-group-events']"
           )

    assert {:ok, nil} = Incubators.configuration(c.admin, group.id)

    view |> form("#incubator-config", profile: attrs) |> render_submit()

    assert {:ok, %{name_en: "New local group", stage: "incubator"}} =
             Incubators.configuration(c.admin, group.id)
  end

  test "event disclosure keeps its URL state and draft through validation and same-group refresh",
       c do
    path = "/manage/groups?group=#{c.group.id}&locale=en"
    {:ok, view, _} = live(log_in_user(build_conn(), c.manager), path)
    refute has_element?(view, "#incubator-next-event[open]")

    view |> element("#incubator-next-event summary") |> render_click()
    assert_patch(view, path <> "&section=next-event")
    assert has_element?(view, "#incubator-next-event[open]")

    view
    |> form("#incubator-config", profile: %{next_event_title_en: "Unsaved event title"})
    |> render_change()

    assert has_element?(view, "#incubator-next-event[open]")

    assert has_element?(
             view,
             "input[name='profile[next_event_title_en]'][value='Unsaved event title']"
           )

    view |> element("#incubator-next-event summary") |> render_click()
    assert_patch(view, path <> "&tab=settings")
    refute has_element?(view, "#incubator-next-event[open]")
    view |> element("#incubator-next-event summary") |> render_click()
    assert_patch(view, path <> "&section=next-event")
    send(view.pid, :refresh_access)
    assert has_element?(view, "#incubator-next-event[open]")

    assert has_element?(
             view,
             "input[name='profile[next_event_title_en]'][value='Unsaved event title']"
           )

    assert {:ok, %{next_event_title_en: nil}} = Incubators.configuration(c.admin, c.group.id)

    {:ok, reloaded, _} = live(log_in_user(build_conn(), c.manager), path <> "&section=next-event")
    assert has_element?(reloaded, "#incubator-next-event[open]")
  end

  test "changing managed group clears the previous event draft and disclosure", c do
    {:ok, other} = Volunteers.create_group(c.admin, %{name: "Other event group"})

    {:ok, _} =
      Incubators.configure(c.admin, other.id, %{
        name_en: "Other event group",
        name_fr: "Autre groupe"
      })

    {:ok, view, _} =
      live(
        log_in_user(build_conn(), c.admin.user),
        "/manage/groups?group=#{c.group.id}&locale=en&section=next-event"
      )

    view
    |> form("#incubator-config", profile: %{next_event_title_en: "Previous group draft"})
    |> render_change()

    render_patch(view, "/manage/groups?group=#{other.id}&locale=en")
    refute has_element?(view, "#incubator-next-event[open]")
    refute has_element?(view, "input[value='Previous group draft']")
    assert has_element?(view, "input[name='profile[name_en]'][value='Other event group']")
  end

  test "group pages keep organizer contact details private", c do
    for locale <- ["en", "fr"] do
      {:ok, view, html} =
        live(log_in_user(build_conn(), c.member), "/groups/#{c.group.id}/join?locale=#{locale}")

      refute html =~ "manager@example.org"
      refute render(view) =~ "manager@example.org"
    end
  end

  test "published incubators offer waitlist and help with localized upcoming event", c do
    assert {:ok, profile} =
             Incubators.configure(
               c.admin,
               c.group.id,
               %{
                 stage: "incubator",
                 next_event_title_en: "Synthetic upcoming event",
                 next_event_title_fr: "Prochaine rencontre fictive",
                 next_event_starts_at: ~U[2099-02-10 18:30:00Z],
                 next_event_timezone: "America/Toronto",
                 next_event_url: "https://example.org/synthetic-event"
               },
               c.profile.revision
             )

    {:ok, view, _} = live(build_conn(), "/en/groups")
    card = "#group-#{c.group.id}"
    assert has_element?(view, card <> " a", "Get involved")
    refute has_element?(view, card <> " a[href*=join]")

    assert has_element?(
             view,
             card <> " time[datetime='2099-02-10T18:30:00Z']",
             "2099-02-10 13:30"
           )

    {:ok, french, _} = live(build_conn(), "/fr/groupes")

    assert has_element?(
             french,
             "#group-next-event-#{c.group.id} a",
             "Prochaine rencontre fictive"
           )

    assert {:ok, _} =
             Incubators.configure(
               c.admin,
               c.group.id,
               %{next_event_starts_at: ~U[2000-01-01 18:30:00Z]},
               profile.revision
             )

    {:ok, past, _} = live(build_conn(), "/en/groups")
    refute has_element?(past, "#group-next-event-#{c.group.id}")
  end

  test "superadmin adds a confirmed existing account with guarded group reference and no invented conduct",
       c do
    {:ok, _} =
      Incubators.configure(c.admin, c.group.id, %{whatsapp_enabled: false}, c.profile.revision)

    {:ok, view, _} =
      live(
        log_in_user(build_conn(), c.admin.user),
        "/manage/groups?group=#{c.group.id}&locale=en"
      )

    assert has_element?(view, "#incubator-add-member")
    params = %{email: c.member.email, role: "manager"}
    view |> form("#incubator-add-member", member: params) |> render_submit()

    membership =
      Repo.get_by!(PauseAiCa.Incubators.Membership, group_id: c.group.id, user_id: c.member.id)

    assert membership.conduct_at == nil
    assert membership.status == "approved"

    assert has_element?(
             view,
             "#membership-#{membership.id}",
             "Conduct acknowledgement has not been recorded"
           )

    count = Repo.aggregate(PauseAiCa.Incubators.Event, :count)
    view |> form("#incubator-add-member", member: params) |> render_submit()
    assert Repo.aggregate(PauseAiCa.Incubators.Event, :count) == count
    assert Enum.any?(Volunteers.groups(Scope.for_user(c.member)), &(&1.id == c.group.id))
    newcomer = user_fixture()

    render_submit(view, "add-existing-member", %{
      "_group_ref" => Ecto.UUID.generate(),
      "member" => %{"email" => newcomer.email, "role" => "member"}
    })

    refute Repo.get_by(PauseAiCa.Incubators.Membership,
             group_id: c.group.id,
             user_id: newcomer.id
           )

    Repo.update!(Ecto.Changeset.change(c.admin.user, superadmin: false))

    render_submit(view, "add-existing-member", %{
      "_group_ref" => c.group.id,
      "member" => %{"email" => newcomer.email, "role" => "member"}
    })

    refute Repo.get_by(PauseAiCa.Incubators.Membership,
             group_id: c.group.id,
             user_id: newcomer.id
           )
  end

  test "ordinary group managers do not see the existing-account enrollment form", c do
    {:ok, view, _} =
      live(log_in_user(build_conn(), c.manager), "/manage/groups?group=#{c.group.id}&locale=en")

    refute has_element?(view, "#incubator-add-member")
  end

  test "superadmins manage all groups without membership or per-group grants", c do
    {:ok, other} = Volunteers.create_group(c.admin, %{name: "Other group"})
    memberships = Repo.aggregate(PauseAiCa.Incubators.Membership, :count)
    grants = Repo.aggregate(PauseAiCa.Volunteers.Manager, :count)

    {:ok, view, _} =
      live(
        log_in_user(build_conn(), c.admin.user),
        "/manage/groups?group=#{c.group.id}&locale=en"
      )

    assert has_element?(view, "#incubator-group-form option[value='#{c.group.id}']")
    assert has_element?(view, "#incubator-group-form option[value='#{other.id}']")

    assert has_element?(
             view,
             "#incubator-superadmin-nonmember",
             "You have full access as a superadmin."
           )

    assert has_element?(view, "#incubator-config")
    assert has_element?(view, "#incubator-roster")

    view |> form("#incubator-group-form", group: other.id) |> render_change()

    view
    |> form("#incubator-config",
      profile: %{
        name_en: "Other group",
        name_fr: "Autre groupe",
        summary_en: "Superadmin configuration"
      }
    )
    |> render_submit()

    assert {:ok, %{summary_en: "Superadmin configuration"}} =
             Incubators.configuration(c.admin, other.id)

    send(view.pid, :refresh_access)
    assert has_element?(view, "#incubator-superadmin-nonmember")
    assert Repo.aggregate(PauseAiCa.Incubators.Membership, :count) == memberships
    assert Repo.aggregate(PauseAiCa.Volunteers.Manager, :count) == grants
    refute Repo.get_by(PauseAiCa.Volunteers.Manager, user_id: c.admin.user.id)
    refute Repo.get_by(PauseAiCa.Incubators.Membership, user_id: c.admin.user.id)
  end

  @tag :empty_groups
  test "superadmin index with no groups remains an empty state through access refresh", c do
    {:ok, view, html} = live(log_in_user(build_conn(), c.admin.user), "/manage/groups?locale=en")
    assert has_element?(view, "#incubator-empty", "No groups have been created yet.")

    assert has_element?(
             view,
             "a[href='/volunteer-signups?locale=en#group-management']",
             "Create a group"
           )

    refute html =~ "You do not manage any groups."
    refute html =~ "This group is unavailable"

    send(view.pid, :refresh_access)
    assert has_element?(view, "#incubator-empty")
    refute has_element?(view, "#incubator-management > [role='alert']")
    assert Repo.aggregate(PauseAiCa.Volunteers.Group, :count) == 0
    assert Repo.aggregate(PauseAiCa.Volunteers.Manager, :count) == 0
    assert Repo.aggregate(PauseAiCa.Incubators.Membership, :count) == 0
    {:ok, group} = Volunteers.create_group(c.admin, %{name: "Newly created group"})
    send(view.pid, :refresh_access)
    assert has_element?(view, "#incubator-group-form option[value='#{group.id}']")
    assert has_element?(view, "#incubator-config")
    assert has_element?(view, "#incubator-superadmin-nonmember")
    refute has_element?(view, "#incubator-management > [role='alert']")
    assert Repo.aggregate(PauseAiCa.Volunteers.Manager, :count) == 0
    assert Repo.aggregate(PauseAiCa.Incubators.Membership, :count) == 0
  end

  @tag :empty_groups
  test "an explicitly unavailable group remains denied for a superadmin", c do
    for id <- ["invalid", Ecto.UUID.generate()] do
      {:ok, view, _} =
        live(log_in_user(build_conn(), c.admin.user), "/manage/groups?group=#{id}&locale=en")

      assert has_element?(view, "[role='alert']", "This group is unavailable")
      refute has_element?(view, "#incubator-empty")
      refute has_element?(view, "#incubator-superadmin-nonmember")
      send(view.pid, :refresh_access)
      assert has_element?(view, "[role='alert']", "This group is unavailable")
    end
  end

  test "nonmember notice follows active membership and fresh superadmin authority", c do
    assert Incubators.superadmin_nonmember?(c.admin, c.group.id)
    refute Incubators.superadmin_nonmember?(c.admin, "invalid")
    refute Incubators.superadmin_nonmember?(c.admin, Ecto.UUID.generate())
    refute Incubators.superadmin_nonmember?(Scope.for_user(c.manager), c.group.id)
    refute Incubators.superadmin_nonmember?(nil, c.group.id)

    membership =
      Repo.insert!(%PauseAiCa.Incubators.Membership{
        group_id: c.group.id,
        user_id: c.admin.user.id,
        display_name: "Superadmin",
        conduct_at: DateTime.utc_now(),
        status: "approved"
      })

    {:ok, view, _} =
      live(
        log_in_user(build_conn(), c.admin.user),
        "/manage/groups?group=#{c.group.id}&locale=en"
      )

    refute has_element?(view, "#incubator-superadmin-nonmember")
    Repo.update!(Ecto.Changeset.change(membership, status: "admitted"))
    refute Incubators.superadmin_nonmember?(c.admin, c.group.id)
    Repo.update!(Ecto.Changeset.change(membership, status: "suspended"))
    send(view.pid, :refresh_access)
    assert has_element?(view, "#incubator-superadmin-nonmember")

    Repo.update!(Ecto.Changeset.change(c.admin.user, superadmin: false))
    refute Incubators.superadmin_nonmember?(c.admin, c.group.id)
    send(view.pid, :refresh_access)
    assert has_element?(view, "[role='alert']", "This group is unavailable")
    refute has_element?(view, "#incubator-config")
    refute has_element?(view, "#incubator-superadmin-nonmember")
  end

  test "bilingual public directory exposes configured groups without invitation or roster", c do
    {:ok, english, html} = live(build_conn(), "/en/groups")
    assert has_element?(english, "h2", "Review local group")
    assert has_element?(english, "#group-#{c.group.id} a", "Get involved")
    assert html =~ "first three characters"
    refute html =~ "private-review-only"
    refute html =~ c.member.email
    {:ok, french, _} = live(build_conn(), "/fr/groupes")
    assert has_element?(french, "h2", "Groupe local de démonstration")
    assert has_element?(french, "p", "trois premiers caractères")
  end

  test "own request, private matching, approval and invitation stay separate", c do
    conn = log_in_user(build_conn(), c.member)
    {:ok, applicant, html} = live(conn, "/groups/#{c.group.id}/join?locale=en")

    assert has_element?(
             applicant,
             "input[name='application[display_name]'][value='Review member']"
           )

    refute html =~ "private-review-only"

    applicant
    |> form("#incubator-application",
      application: %{display_name: "Review member", identifier: "+15555550100", conduct: "true"}
    )
    |> render_submit()

    assert has_element?(applicant, "#my-membership", "Pending review")
    applicant |> element("button", "Create private matching reference") |> render_click()

    [_, reference] =
      Regex.run(
        ~r/<strong[^>]*>([A-Za-z0-9_-]+)<\/strong>/,
        applicant |> element("#matching-reference strong") |> render()
      )

    assert has_element?(applicant, "#matching-reference", "15 minutes")
    {:ok, m} = Incubators.mine(Scope.for_user(c.member), c.group.id)

    {:ok, manager, html} =
      live(log_in_user(build_conn(), c.manager), "/manage/groups?group=#{c.group.id}&locale=en")

    refute html =~ reference
    manager |> form("#match-#{m.id}", member: %{reference: reference}) |> render_submit()
    assert has_element?(manager, "#membership-#{m.id}", "Identifier matched")

    render_submit(manager, "decide", %{
      "decision" => "approve",
      "member" => %{"id" => m.id, "revision" => "3"}
    })

    assert has_element?(manager, "#membership-#{m.id}", "Approved")
    {:ok, applicant, html} = live(conn, "/groups/#{c.group.id}/join?locale=en")
    refute html =~ "private-review-only"
    applicant |> element("button", "Show my invitation") |> render_click()
    assert has_element?(applicant, "a[href='https://chat.whatsapp.com/private-review-only']")
    assert has_element?(applicant, "#my-membership", "must approve admission")
    assert {:ok, %{status: "approved"}} = Incubators.mine(Scope.for_user(c.member), c.group.id)
  end

  test "access refresh does not advance an edited request's revision", c do
    scope = Scope.for_user(c.member)

    {:ok, membership} =
      Incubators.request(scope, c.group.id, %{
        "display_name" => "Original",
        "identifier" => "first",
        "conduct" => true
      })

    {:ok, view, _} =
      live(log_in_user(build_conn(), c.member), "/groups/#{c.group.id}/join?locale=en")

    {:ok, _} =
      Incubators.request(
        scope,
        c.group.id,
        %{"display_name" => "Other tab", "identifier" => "second", "conduct" => true},
        membership.revision
      )

    send(view.pid, :refresh_access)
    assert render(view) =~ "This record changed"

    view
    |> form("#incubator-application",
      application: %{display_name: "My unsaved draft", identifier: "mine", conduct: "true"}
    )
    |> render_submit()

    assert has_element?(view, "input[name='application[display_name]'][value='My unsaved draft']")
    assert {:ok, %{display_name: "Other tab"}} = Incubators.mine(scope, c.group.id)
    assert has_element?(view, "button", "Reload request")
  end

  test "invalid configuration shows field feedback and revoked manager loses private roster", c do
    {:ok, _} =
      Incubators.request(Scope.for_user(c.member), c.group.id, %{
        "display_name" => "Private member",
        "identifier" => "private-identifier",
        "conduct" => true
      })

    {:ok, view, _} =
      live(log_in_user(build_conn(), c.manager), "/manage/groups?group=#{c.group.id}&locale=en")

    view
    |> form("#incubator-config", profile: %{name_en: "Name", name_fr: "Nom", fsas: "invalid"})
    |> render_submit()

    assert has_element?(view, "input[name='profile[fsas]'][value='invalid']")
    assert render(view) =~ "first three postal-code characters"
    :ok = Volunteers.revoke_manager(c.admin, c.grant.id)
    send(view.pid, :refresh_access)
    html = render(view)
    refute html =~ "private-identifier"
    refute has_element?(view, "#incubator-config")
  end

  test "public directory ignores application events without a selected group", _c do
    {:ok, view, _} = live(build_conn(), "/en/groups")
    render_submit(view, "save", %{"application" => %{"display_name" => "Unexpected"}})
    assert has_element?(view, "#incubators")
    assert Repo.aggregate(PauseAiCa.Incubators.Membership, :count) == 0
  end

  test "roster actions preserve the configuration draft and original revision", c do
    {:ok, member} =
      Incubators.request(Scope.for_user(c.member), c.group.id, %{
        "display_name" => "Pending member",
        "identifier" => "pending",
        "conduct" => true
      })

    {:ok, view, _} =
      live(log_in_user(build_conn(), c.manager), "/manage/groups?group=#{c.group.id}&locale=en")

    view
    |> form("#incubator-config", profile: %{summary_en: "Unsaved configuration draft"})
    |> render_change()

    render_submit(view, "decide", %{
      "decision" => "reject",
      "member" => %{
        "id" => member.id,
        "revision" => to_string(member.revision),
        "reason" => "Synthetic review reason"
      }
    })

    assert has_element?(view, "#membership-#{member.id}", "Declined")

    assert has_element?(
             view,
             "textarea[name='profile[summary_en]']",
             "Unsaved configuration draft"
           )

    assert has_element?(view, "input[name='_profile_revision'][value='#{c.profile.revision}']")
    assert {:ok, %{summary_en: ""}} = Incubators.configuration(c.admin, c.group.id)
  end

  test "groups without external admission do not offer an unusable reference matcher", c do
    {:ok, _} =
      Incubators.configure(
        c.admin,
        c.group.id,
        %{"whatsapp_enabled" => false},
        c.profile.revision
      )

    {:ok, member} =
      Incubators.request(Scope.for_user(c.member), c.group.id, %{
        "display_name" => "Local member",
        "conduct" => true
      })

    {:ok, view, _} =
      live(log_in_user(build_conn(), c.manager), "/manage/groups?group=#{c.group.id}&locale=en")

    refute has_element?(view, "#match-#{member.id}")
    assert has_element?(view, "#decision-#{member.id} button[value=approve]")
  end
end
