defmodule PauseAiCa.WelcomeTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Welcome, Volunteers, Mail}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Welcome.{Session, Participant, Event}

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    admin_scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(admin_scope, %{name: "Welcome group"})
    manager = user_fixture()
    {:ok, grant} = Volunteers.assign_manager(admin_scope, group.id, manager.email)
    newcomer = user_fixture() |> change(organizing_group_id: group.id) |> Repo.update!()

    %{
      admin: admin_scope,
      scope: Scope.for_user(manager),
      group: group,
      manager: manager,
      newcomer: newcomer,
      grant: grant
    }
  end

  defp attrs(c, overrides \\ %{}) do
    Map.merge(
      %{
        "title" => "Welcome to the group",
        "host_id" => c.manager.id,
        "language" => "en",
        "timezone" => "America/Toronto",
        "starts_at" => DateTime.add(DateTime.utc_now(), 3600),
        "ends_at" => DateTime.add(DateTime.utc_now(), 7200),
        "meeting_url" => "https://example.org/welcome"
      },
      overrides
    )
  end

  test "selected cohort produces exact private drafts without recording an invitation or granting consent",
       c do
    {:ok, session} = Welcome.create(c.scope, c.group.id, attrs(c), "create")

    {:ok, selected} =
      Welcome.select(c.scope, c.group.id, session.id, [c.newcomer.id], session.revision, "select")

    {:ok, batch} =
      Welcome.prepare_drafts(
        c.scope,
        c.group.id,
        session.id,
        [c.newcomer.id],
        selected.revision,
        "draft"
      )

    assert batch.recipient_ids == [c.newcomer.id]
    assert {:ok, drafts} = Mail.drafts(c.scope, batch.id)
    assert [%{email: email}] = drafts
    assert email == c.newcomer.email
    p = Repo.one!(Participant)
    assert p.invitation_state == "selected" and p.rsvp == "pending" and p.attendance == "unknown"
    assert p.draft_batch_id == batch.id

    assert {:ok, replay} =
             Welcome.prepare_drafts(
               c.scope,
               c.group.id,
               session.id,
               [c.newcomer.id],
               selected.revision,
               "draft"
             )

    assert replay.id == batch.id
    assert Repo.aggregate(PauseAiCa.Mail.Batch, :count) == 1
    assert Repo.aggregate(PauseAiCa.Mail.Draft, :count) == 1
    assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
    assert Repo.aggregate(PauseAiCa.Newsletters.Delivery, :count) == 0
    assert Repo.aggregate(PauseAiCa.Volunteers.Manager, :count) == 1
  end

  test "owned RSVP and human outcomes stay distinct, with fresh manager revocation", c do
    {:ok, session} = Welcome.create(c.scope, c.group.id, attrs(c), "create")

    {:ok, _} =
      Welcome.select(c.scope, c.group.id, session.id, [c.newcomer.id], session.revision, "select")

    p = Repo.one!(Participant)

    {:ok, invited} =
      Welcome.record_invited(c.scope, c.group.id, session.id, p.id, p.revision, "invited")

    outsider = Scope.for_user(user_fixture())

    assert {:error, :unauthorized} =
             Welcome.respond(outsider, p.id, "accepted", invited.revision, "no")

    {:ok, accepted} =
      Welcome.respond(Scope.for_user(c.newcomer), p.id, "accepted", invited.revision, "accept")

    assert accepted.rsvp == "accepted" and accepted.attendance == "unknown"
    assert accepted.follow_up == "pending"

    assert {:error, :not_started} =
             Welcome.record_outcome(
               c.scope,
               c.group.id,
               session.id,
               p.id,
               %{"attendance" => "attended"},
               accepted.revision,
               "too-early"
             )

    Repo.update!(
      change(Repo.get!(Session, session.id),
        starts_at: DateTime.add(DateTime.utc_now(), -7200),
        ends_at: DateTime.add(DateTime.utc_now(), -3600)
      )
    )

    {:ok, attended} =
      Welcome.record_outcome(
        c.scope,
        c.group.id,
        session.id,
        p.id,
        %{
          "attendance" => "attended",
          "follow_up" => "completed",
          "notes" => "Send the resources"
        },
        accepted.revision,
        "outcome"
      )

    assert attended.attendance == "attended" and attended.rsvp == "accepted"
    assert attended.attendance_by_id == c.manager.id
    :ok = Volunteers.revoke_manager(c.admin, c.grant.id)
    assert {:error, :unauthorized} = Welcome.get(c.scope, c.group.id, session.id)

    assert {:error, :unauthorized} =
             Welcome.record_outcome(
               c.scope,
               c.group.id,
               session.id,
               p.id,
               %{"attendance" => "no_show"},
               attended.revision,
               "revoked"
             )

    {:ok, [own]} = Welcome.mine(Scope.for_user(c.newcomer))
    assert own.id == p.id
  end

  test "moving a selected person retains history and prevents parallel active calls; withdrawals suppress new selection",
       c do
    {:ok, one} = Welcome.create(c.scope, c.group.id, attrs(c), "one")
    {:ok, two} = Welcome.create(c.scope, c.group.id, attrs(c, %{"title" => "Next call"}), "two")

    {:ok, _} =
      Welcome.select(c.scope, c.group.id, one.id, [c.newcomer.id], one.revision, "select")

    assert {:error, :already_scheduled} =
             Welcome.select(
               c.scope,
               c.group.id,
               two.id,
               [c.newcomer.id],
               two.revision,
               "duplicate"
             )

    old = Repo.one!(Participant)
    {:ok, moved} = Welcome.move(c.scope, c.group.id, old.id, two.id, old.revision, "move")
    assert Repo.get!(Participant, old.id).invitation_state == "moved"
    assert moved.session_id == two.id and moved.invitation_state == "selected"

    {:ok, invited} =
      Welcome.record_invited(c.scope, c.group.id, two.id, moved.id, moved.revision, "invite")

    {:ok, withdrawn} =
      Welcome.respond(
        Scope.for_user(c.newcomer),
        moved.id,
        "withdrawn",
        invited.revision,
        "withdraw"
      )

    assert withdrawn.rsvp == "withdrawn"

    {:ok, three} =
      Welcome.create(c.scope, c.group.id, attrs(c, %{"title" => "Third call"}), "three")

    assert {:error, :ineligible} =
             Welcome.select(
               c.scope,
               c.group.id,
               three.id,
               [c.newcomer.id],
               three.revision,
               "no-reinvite"
             )
  end

  test "foreign group, stale revision and invalid hosts cannot mutate sessions", c do
    other = user_fixture()
    {:ok, foreign} = Volunteers.create_group(c.admin, %{name: "Other group"})
    {:ok, _} = Volunteers.assign_manager(c.admin, foreign.id, other.email)

    assert {:error, _} =
             Welcome.create(c.scope, c.group.id, attrs(c, %{"host_id" => other.id}), "bad-host")

    {:ok, session} = Welcome.create(c.scope, c.group.id, attrs(c), "create")
    assert {:error, :unauthorized} = Welcome.get(Scope.for_user(other), c.group.id, session.id)

    {:ok, updated} =
      Welcome.update(
        c.scope,
        c.group.id,
        session.id,
        %{"title" => "Updated"},
        session.revision,
        "update"
      )

    assert {:error, :conflict} =
             Welcome.update(
               c.scope,
               c.group.id,
               session.id,
               %{"title" => "Stale"},
               session.revision,
               "stale"
             )

    assert Repo.get!(Session, session.id).title == updated.title
    assert Repo.aggregate(Event, :count) == 2
  end

  test "IANA local-time conversion rejects clock gaps and ambiguous repeated time" do
    assert {:ok, time} = Welcome.local_time("2026-11-15T15:00", "America/Toronto")
    assert DateTime.to_iso8601(time) =~ "2026-11-15T20:00:00"
    assert {:error, :clock_change} = Welcome.local_time("2026-03-08T02:30", "America/Toronto")
    assert {:error, :clock_change} = Welcome.local_time("2026-11-01T01:30", "America/Toronto")
    assert {:error, :invalid_time} = Welcome.local_time("2026-11-15T15:00", "Invented/Zone")
  end

  test "a removed host blocks new invitation preparation even while another manager retains authority",
       c do
    other = user_fixture()
    {:ok, _} = Volunteers.assign_manager(c.admin, c.group.id, other.email)
    other_scope = Scope.for_user(other)
    {:ok, session} = Welcome.create(other_scope, c.group.id, attrs(c), "create")

    {:ok, selected} =
      Welcome.select(
        other_scope,
        c.group.id,
        session.id,
        [c.newcomer.id],
        session.revision,
        "select"
      )

    p = Repo.one!(Participant)
    :ok = Volunteers.revoke_manager(c.admin, c.grant.id)

    assert {:error, :session_closed} =
             Welcome.prepare_drafts(
               other_scope,
               c.group.id,
               session.id,
               [c.newcomer.id],
               selected.revision,
               "draft"
             )

    assert {:error, :ineligible} =
             Welcome.record_invited(
               other_scope,
               c.group.id,
               session.id,
               p.id,
               p.revision,
               "invite"
             )

    assert Repo.aggregate(PauseAiCa.Mail.Batch, :count) == 0
    assert Repo.get!(Participant, p.id).invitation_state == "selected"
  end
end
