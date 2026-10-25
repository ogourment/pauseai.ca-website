defmodule PauseAiCa.IncubatorsTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Incubators, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Incubators.{Membership, Event}

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!() |> Scope.for_user()
    manager = user_fixture()
    member = user_fixture()
    {:ok, group} = Volunteers.create_group(admin, %{name: "Configured group"})
    {:ok, other} = Volunteers.create_group(admin, %{name: "Other group"})
    {:ok, grant} = Volunteers.assign_manager(admin, group.id, manager.email)

    attrs = %{
      "name_en" => "Local group",
      "name_fr" => "Groupe local",
      "published" => true,
      "fsas" => "H2X, H2Y",
      "whatsapp_enabled" => true,
      "whatsapp_approval_confirmed" => true,
      "moderator_contact" => "moderators@example.org",
      "whatsapp_invite_url" => "https://chat.whatsapp.com/synthetic-private"
    }

    {:ok, profile} = Incubators.configure(admin, group.id, attrs)

    %{
      admin: admin,
      manager: Scope.for_user(manager),
      member: Scope.for_user(member),
      group: group,
      other: other,
      grant: grant,
      profile: profile
    }
  end

  defp apply_request(c, identifier \\ "@synthetic_member") do
    {:ok, m} =
      Incubators.request(c.member, c.group.id, %{
        "display_name" => "Review member",
        "identifier" => identifier,
        "conduct" => "true"
      })

    m
  end

  defp matched(c) do
    m = apply_request(c)
    {:ok, issued} = Incubators.issue_reference(c.member, c.group.id, m.revision)

    {:ok, m} =
      Incubators.match_reference(
        c.manager,
        c.group.id,
        m.id,
        issued.reference,
        issued.membership.revision
      )

    m
  end

  test "configured directory publishes safe fields and matches FSA without city branches", c do
    assert [%{group_id: id, fsas: ["H2X", "H2Y"]} = public] = Incubators.public_groups("H2X")
    assert id == c.group.id
    refute Map.has_key?(public, :whatsapp_invite_url)
    assert {:error, :not_found} = Incubators.public_group("invalid")
    assert {:error, :forbidden} = Incubators.withdraw(c.member, Ecto.UUID.generate(), 1)

    assert {:error, :forbidden} =
             Incubators.configure(
               c.manager,
               c.group.id,
               %{"published" => false},
               c.profile.revision
             )

    assert {:error, :forbidden} =
             Incubators.configure(c.manager, c.group.id, %{published: false}, c.profile.revision)

    assert {:ok, p} =
             Incubators.configure(
               c.manager,
               c.group.id,
               %{"summary_en" => "Updated"},
               c.profile.revision
             )

    assert p.fsas == ["H2X", "H2Y"]

    assert {:error, :stale} =
             Incubators.configure(
               c.admin,
               c.group.id,
               %{"summary_en" => "Stale"},
               c.profile.revision
             )

    assert {:error, cs} =
             Incubators.configure(
               c.admin,
               c.group.id,
               %{"events_url" => "javascript:bad"},
               p.revision
             )

    assert cs.errors[:events_url]
  end

  test "account-specific requests support several groups without granting authority", c do
    m = apply_request(c)
    assert m.status == "pending"

    assert {:error, :stale} =
             Incubators.request(c.member, c.group.id, %{
               "display_name" => "Duplicate",
               "conduct" => true
             })

    assert Repo.aggregate(Membership, :count) == 1
    assert Volunteers.groups(c.member) == []
    assert {:error, :forbidden} = Incubators.roster(c.member, c.group.id)

    assert {:ok, _} =
             Incubators.configure(c.admin, c.other.id, %{
               "name_en" => "Second",
               "name_fr" => "Deuxième",
               "published" => true
             })

    assert {:ok, _} =
             Incubators.request(c.member, c.other.id, %{
               "display_name" => "Same member",
               "conduct" => true
             })

    assert Repo.aggregate(Membership, :count) == 2

    unconfirmed =
      user_fixture() |> change(confirmed_at: nil) |> Repo.update!() |> Scope.for_user()

    assert {:error, :forbidden} = Incubators.request(unconfirmed, c.group.id, %{})
  end

  test "private reference is hashed, rate-limited, single-use and omitted from history", c do
    m = apply_request(c)
    {:ok, issued} = Incubators.issue_reference(c.member, c.group.id, m.revision)
    stored = Repo.get!(Membership, m.id)
    assert stored.code_hash != issued.reference

    assert {:error, :cooldown} =
             Incubators.issue_reference(c.member, c.group.id, issued.membership.revision)

    assert {:error, :invalid_reference} =
             Incubators.match_reference(c.manager, c.group.id, m.id, "wrong", stored.revision)

    {:ok, verified} =
      Incubators.match_reference(c.manager, c.group.id, m.id, issued.reference, stored.revision)

    assert verified.matched_at
    assert Repo.get!(Membership, m.id).code_hash == nil

    assert {:error, :invalid_reference} =
             Incubators.match_reference(
               c.manager,
               c.group.id,
               m.id,
               issued.reference,
               verified.revision
             )

    refute inspect(Repo.all(Event)) =~ issued.reference
    {:ok, roster} = Incubators.roster(c.manager, c.group.id)
    refute Map.has_key?(hd(roster), :code_hash)
  end

  test "reference expiry and attempt budget cannot be bypassed", c do
    m = apply_request(c)
    {:ok, issued} = Incubators.issue_reference(c.member, c.group.id, m.revision)

    for _ <- 1..5 do
      assert {:error, :invalid_reference} =
               Incubators.match_reference(
                 c.manager,
                 c.group.id,
                 m.id,
                 "wrong",
                 issued.membership.revision
               )
    end

    assert {:error, :invalid_reference} =
             Incubators.match_reference(
               c.manager,
               c.group.id,
               m.id,
               issued.reference,
               issued.membership.revision
             )

    Repo.get!(Membership, m.id)
    |> change(code_attempts: 0, code_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:error, :invalid_reference} =
             Incubators.match_reference(
               c.manager,
               c.group.id,
               m.id,
               issued.reference,
               issued.membership.revision
             )
  end

  test "approval does not manufacture external admission and withdrawal requires reconciliation",
       c do
    m = apply_request(c)

    assert {:error, :matching_required} =
             Incubators.decide(c.manager, c.group.id, m.id, :approve, %{}, m.revision)

    {:ok, issued} = Incubators.issue_reference(c.member, c.group.id, m.revision)

    {:ok, m} =
      Incubators.match_reference(
        c.manager,
        c.group.id,
        m.id,
        issued.reference,
        issued.membership.revision
      )

    {:ok, m} = Incubators.decide(c.manager, c.group.id, m.id, :approve, %{}, m.revision)

    assert {:ok, "https://chat.whatsapp.com/synthetic-private"} =
             Incubators.invitation(c.member, c.group.id)

    assert {:error, :observation_required} =
             Incubators.decide(c.manager, c.group.id, m.id, :admit, %{}, m.revision)

    {:ok, m} =
      Incubators.decide(
        c.manager,
        c.group.id,
        m.id,
        :admit,
        %{"observed_admission" => true},
        m.revision
      )

    {:ok, m} = Incubators.withdraw(c.member, c.group.id, m.revision)
    assert m.external_removal_pending
    assert {:error, :forbidden} = Incubators.invitation(c.member, c.group.id)

    assert {:error, :removal_pending} =
             Incubators.request(
               c.member,
               c.group.id,
               %{"display_name" => "Again", "conduct" => true},
               m.revision
             )

    {:ok, m} = Incubators.confirm_removal(c.manager, c.group.id, m.id, m.revision)
    refute m.external_removal_pending
  end

  test "fresh authority and scope protect every manager operation", c do
    m = matched(c)
    outsider = Scope.for_user(user_fixture())
    {:ok, _} = Volunteers.assign_manager(c.admin, c.other.id, outsider.user.email)
    assert {:error, :forbidden} = Incubators.roster(outsider, c.group.id)
    assert {:error, :forbidden} = Incubators.activity(outsider, c.group.id)

    assert {:error, :forbidden} =
             Incubators.decide(outsider, c.group.id, m.id, :approve, %{}, m.revision)

    assert {:error, :stale} =
             Incubators.decide(c.manager, c.group.id, Ecto.UUID.generate(), :approve, %{}, 1)

    assert :ok = Volunteers.revoke_manager(c.admin, c.grant.id)

    assert {:error, :forbidden} =
             Incubators.decide(c.manager, c.group.id, m.id, :approve, %{}, m.revision)

    assert {:error, :forbidden} = Incubators.roster(c.manager, c.group.id)
  end

  test "changing an identifier clears matching and old revisions cannot approve", c do
    m = matched(c)

    {:ok, updated} =
      Incubators.request(
        c.member,
        c.group.id,
        %{
          "display_name" => "Review member",
          "identifier" => "@new_identifier",
          "conduct" => true
        },
        m.revision
      )

    refute updated.matched_at

    assert {:error, :stale} =
             Incubators.decide(c.manager, c.group.id, m.id, :approve, %{}, m.revision)

    assert {:error, :matching_required} =
             Incubators.decide(c.manager, c.group.id, m.id, :approve, %{}, updated.revision)
  end

  test "delegation is explicit, coordinators gain no organizer role and last manager is protected",
       c do
    m = matched(c)

    assert {:error, :approval_required} =
             Incubators.delegate(c.manager, c.group.id, m.id, "manager", m.revision)

    {:ok, m} = Incubators.decide(c.manager, c.group.id, m.id, :approve, %{}, m.revision)
    {:ok, m} = Incubators.delegate(c.manager, c.group.id, m.id, "coordinator", m.revision)
    assert Volunteers.groups(c.member) == []
    {:ok, m} = Incubators.delegate(c.manager, c.group.id, m.id, "manager", m.revision)
    assert Enum.any?(Volunteers.groups(c.member), &(&1.id == c.group.id))
    :ok = Volunteers.revoke_manager(c.admin, c.grant.id)
    assert {:error, :last_manager} = Incubators.withdraw(c.member, c.group.id, m.revision)

    assert {:error, :last_manager} =
             Incubators.delegate(c.member, c.group.id, m.id, "member", m.revision)
  end

  test "enabling external discussion does not turn prior local approval into matched identity",
       c do
    {:ok, p} =
      Incubators.configure(
        c.admin,
        c.group.id,
        %{"whatsapp_enabled" => false},
        c.profile.revision
      )

    m = apply_request(c)
    {:ok, _} = Incubators.decide(c.manager, c.group.id, m.id, :approve, %{}, m.revision)

    {:ok, _} =
      Incubators.configure(c.admin, c.group.id, %{"whatsapp_enabled" => true}, p.revision)

    assert {:error, :forbidden} = Incubators.invitation(c.member, c.group.id)
  end
end
