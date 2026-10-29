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
    assert has_element?(english, "a[href='/groups/#{c.group.id}/join?locale=en']")
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
