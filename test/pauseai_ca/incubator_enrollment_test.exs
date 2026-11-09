defmodule PauseAiCa.IncubatorEnrollmentTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Incubators, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Incubators.{Membership, Event}

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!() |> Scope.for_user()
    member = user_fixture()
    manager = user_fixture()
    {:ok, group} = Volunteers.create_group(admin, %{name: "Enrollment group"})
    {:ok, _} = Volunteers.assign_manager(admin, group.id, manager.email)

    {:ok, profile} =
      Incubators.configure(admin, group.id, %{
        name_en: "Enrollment",
        name_fr: "Adhésion",
        published: true
      })

    %{admin: admin, member: member, manager: manager, group: group, profile: profile}
  end

  test "admin enrollment records its actor without claiming conduct and replay creates no events",
       c do
    assert {:ok, added} =
             Incubators.add_existing_member(c.admin, c.group.id, c.member.email, "manager")

    row = Repo.get!(Membership, added.id)
    assert row.status == "approved"
    assert row.role == "manager"
    assert row.conduct_at == nil
    assert Enum.any?(Volunteers.groups(Scope.for_user(c.member)), &(&1.id == c.group.id))
    refute Repo.get!(PauseAiCa.Accounts.User, c.member.id).superadmin
    event = Repo.get_by!(Event, membership_id: row.id, action: "member_added")
    assert event.actor_id == c.admin.user.id
    assert event.details["source"] == "admin_enrollment"
    assert event.details["conduct_acknowledged"] == false

    refute Repo.exists?(
             from e in Event, where: e.membership_id == ^row.id and e.action == "request"
           )

    count = Repo.aggregate(Event, :count)

    assert {:ok, repeated} =
             Incubators.add_existing_member(c.admin, c.group.id, c.member.email, "manager")

    assert repeated.id == row.id
    assert Repo.aggregate(Event, :count) == count
  end

  test "explicit enrollment reconciles legacy manager registry drift in both directions", c do
    {:ok, added} = Incubators.add_existing_member(c.admin, c.group.id, c.member.email, "manager")
    grant = Repo.get_by!(PauseAiCa.Volunteers.Manager, group_id: c.group.id, user_id: c.member.id)
    :ok = Volunteers.revoke_manager(c.admin, grant.id)

    assert {:ok, restored} =
             Incubators.add_existing_member(c.admin, c.group.id, c.member.email, "manager")

    assert restored.revision > added.revision
    assert Enum.any?(Volunteers.groups(Scope.for_user(c.member)), &(&1.id == c.group.id))

    {:ok, demoted} =
      Incubators.delegate(c.admin, c.group.id, restored.id, "member", restored.revision)

    {:ok, _} = Volunteers.assign_manager(c.admin, c.group.id, c.member.email)

    assert {:ok, reconciled} =
             Incubators.add_existing_member(c.admin, c.group.id, c.member.email, "member")

    assert reconciled.revision > demoted.revision
    assert reconciled.role == "member"
    refute Enum.any?(Volunteers.groups(Scope.for_user(c.member)), &(&1.id == c.group.id))
  end

  test "ordinary managers, unconfirmed targets and revoked superadmins cannot enroll", c do
    assert {:error, :forbidden} =
             Incubators.add_existing_member(
               Scope.for_user(c.manager),
               c.group.id,
               c.member.email,
               "member"
             )

    unconfirmed = unconfirmed_user_fixture()

    assert {:error, :confirmed_account_required} =
             Incubators.add_existing_member(c.admin, c.group.id, unconfirmed.email, "member")

    Repo.update!(change(c.admin.user, confirmed_at: nil))

    assert {:error, :forbidden} =
             Incubators.add_existing_member(c.admin, c.group.id, c.member.email, "member")

    Repo.update!(change(c.admin.user, superadmin: false, confirmed_at: DateTime.utc_now(:second)))

    assert {:error, :forbidden} =
             Incubators.add_existing_member(c.admin, c.group.id, c.member.email, "member")

    assert Repo.aggregate(Membership, :count) == 0
  end

  test "enrollment does not reactivate withdrawal or bypass WhatsApp identity matching", c do
    {:ok, request} =
      Incubators.request(Scope.for_user(c.member), c.group.id, %{
        "display_name" => "Member",
        "conduct" => true
      })

    {:ok, _} = Incubators.withdraw(Scope.for_user(c.member), c.group.id, request.revision)

    assert {:error, :reactivation_not_allowed} =
             Incubators.add_existing_member(c.admin, c.group.id, c.member.email, "member")

    {:ok, _} =
      Incubators.configure(
        c.admin,
        c.group.id,
        %{
          whatsapp_enabled: true,
          whatsapp_approval_confirmed: true,
          moderator_contact: "manager@example.org"
        },
        c.profile.revision
      )

    newcomer = user_fixture()

    assert {:error, :matching_required} =
             Incubators.add_existing_member(c.admin, c.group.id, newcomer.email, "manager")

    refute Repo.get_by(Membership, group_id: c.group.id, user_id: newcomer.id)
    refute Enum.any?(Volunteers.groups(Scope.for_user(newcomer)), &(&1.id == c.group.id))
  end

  test "normal self-request still requires an actual conduct acknowledgement", c do
    assert {:error, %Ecto.Changeset{}} =
             Incubators.request(Scope.for_user(c.member), c.group.id, %{
               "display_name" => "Member"
             })

    assert {:ok, added} =
             Incubators.add_existing_member(c.admin, c.group.id, c.member.email, "member")

    assert Repo.get!(Membership, added.id).conduct_at == nil
  end
end
