defmodule PauseAiCa.MailAccessTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Mail, Outreach}
  alias PauseAiCa.Volunteers.{Group, Manager}

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    manager = user_fixture() |> change(superadmin: false) |> Repo.update!()
    ordinary = user_fixture() |> change(superadmin: false) |> Repo.update!()
    group = Repo.insert!(%Group{name: "Synthetic email-tool access"})
    role = Repo.insert!(%Manager{group_id: group.id, user_id: manager.id})
    previous = Application.get_env(:pauseai_ca, :outreach_mailboxes)

    Application.put_env(:pauseai_ca, :outreach_mailboxes, [
      %{
        id: "outreach_en",
        name: "Synthetic sender",
        email: "hello@example.org",
        locale: "en",
        owner_id: admin.id,
        receiving_addresses: ["reply@example.org"],
        enabled?: true,
        verified?: true
      }
    ])

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pauseai_ca, :outreach_mailboxes, previous),
        else: Application.delete_env(:pauseai_ca, :outreach_mailboxes)
    end)

    %{
      admin: admin,
      admin_scope: Accounts.Scope.for_user(admin),
      manager: manager,
      scope: Accounts.Scope.for_user(manager),
      ordinary: ordinary,
      group: group,
      role: role
    }
  end

  test "anonymous, ordinary and unconfirmed accounts have no email tools even with cached privilege",
       c do
    denied = %{legacy?: false, outreach?: false, any?: false}
    assert Mail.capabilities(nil) == denied
    assert Mail.capabilities(Accounts.Scope.for_user(c.ordinary)) == denied
    Repo.update!(change(c.admin, confirmed_at: nil))
    assert Mail.capabilities(c.admin_scope) == denied
    refute Mail.access?(c.admin_scope)
  end

  test "zero mailbox grants preserves actual existing scoped group-account mail preparation", c do
    assert Mail.capabilities(c.scope) == %{legacy?: true, outreach?: false, any?: true}
    assert {:ok, []} = Outreach.mailboxes(c.scope)
    member = Repo.update!(change(c.ordinary, organizing_group_id: c.group.id))
    assert {:ok, batch} = Mail.create(c.scope, member.id)
    assert {:ok, %{id: id}} = Mail.get(c.scope, batch.id)
    assert id == batch.id
    assert {:error, :unauthorized} = Outreach.get(c.scope, Ecto.UUID.generate())
  end

  test "grants affect mailbox tools only; revoking the manager role removes all email access freshly",
       c do
    assert {:ok, _} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 0)
    assert Mail.capabilities(c.scope) == %{legacy?: true, outreach?: true, any?: true}
    assert {:ok, _} = Outreach.revoke_mailbox(c.admin_scope, "outreach_en", c.manager.id, 1)
    assert Mail.capabilities(c.scope) == %{legacy?: true, outreach?: false, any?: true}
    assert {:ok, _} = Outreach.grant_mailbox(c.admin_scope, "outreach_en", c.manager.id, 2)
    Repo.delete!(c.role)
    assert Mail.capabilities(c.scope) == %{legacy?: false, outreach?: false, any?: false}
    refute Mail.access?(c.scope)
  end

  test "superadmin tools are fresh and independent of configured mailbox availability", c do
    assert Mail.capabilities(c.admin_scope) == %{legacy?: true, outreach?: true, any?: true}
    Application.put_env(:pauseai_ca, :outreach_mailboxes, [])
    assert Mail.capabilities(c.admin_scope) == %{legacy?: true, outreach?: false, any?: true}
    Repo.update!(change(c.admin, superadmin: false))
    assert Mail.capabilities(c.admin_scope) == %{legacy?: false, outreach?: false, any?: false}
  end
end
