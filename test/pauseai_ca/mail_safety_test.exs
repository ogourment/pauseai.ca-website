defmodule PauseAiCa.MailSafetyTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  import Swoosh.Email, except: [from: 2]
  alias PauseAiCa.{Mailer, MailSafety}

  setup do
    previous = Application.fetch_env!(:pauseai_ca, :mail_environment)
    admin = unconfirmed_user_fixture()

    admin =
      admin
      |> Ecto.Changeset.change(superadmin: true, confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    Application.put_env(:pauseai_ca, :mail_environment, :staging)
    on_exit(fn -> Application.put_env(:pauseai_ca, :mail_environment, previous) end)
    %{admin: admin}
  end

  defp message do
    new()
    |> Swoosh.Email.from("sender@example.org")
    |> to("member@example.org")
    |> cc("copy@example.org")
    |> bcc("hidden@example.org")
    |> reply_to("member@example.org")
    |> subject("Review")
    |> text_body("Draft body")
  end

  test "STAGE-MAIL-01 sends only to the authorizing admin, across single and bulk paths", %{
    admin: admin
  } do
    opts = [admin_actor_id: admin.id]
    assert {:ok, _} = Mailer.deliver(message(), opts)
    assert_receive {:email, delivered}
    assert delivered.to == [{"Staging admin", admin.email}]
    assert delivered.cc == [] and delivered.bcc == [] and delivered.reply_to == nil
    assert delivered.subject == "[STAGING] Review"
    assert delivered.text_body == "Draft body"
    assert {:ok, _} = Mailer.deliver_many([message()], opts)
    assert_receive {:emails, [bulk]}
    assert bulk.to == delivered.to and bulk.cc == [] and bulk.bcc == []
    Mailer.deliver!(message(), opts)
    assert_receive {:email, _}
  end

  test "missing, invalid and revoked authorization never submits", %{admin: admin} do
    assert {:error, :staging_admin_required} = Mailer.deliver(message())
    assert {:error, :staging_admin_required} = Mailer.deliver_many([message()])
    assert {:error, :staging_admin_required} = Mailer.deliver(message(), admin_actor_id: "bad")
    Repo.update!(Ecto.Changeset.change(admin, superadmin: false))
    assert {:error, :staging_admin_required} = Mailer.deliver(message(), admin_actor_id: admin.id)
    refute_receive {:email, _}
  end

  test "unknown environment and newsletter writes fail closed" do
    assert {:error, :not_configured} =
             PauseAiCa.Campaigns.Subscription.subscribe("member@example.org", "en")

    Application.put_env(:pauseai_ca, :mail_environment, :unknown)
    assert {:error, :mail_environment_blocked} = Mailer.deliver(message())
    refute MailSafety.provider_writes_allowed?()
    refute_receive {:email, _}
  end

  test "production preserves the original envelope" do
    Application.put_env(:pauseai_ca, :mail_environment, :production)
    assert {:ok, _} = Mailer.deliver(message())
    assert_receive {:email, delivered}
    assert delivered == message()
  end

  test "confirmed group managers are allowed, and revocation takes effect immediately", %{
    admin: admin
  } do
    actor = unconfirmed_user_fixture()
    actor = Repo.update!(Ecto.Changeset.change(actor, confirmed_at: DateTime.utc_now(:second)))
    scope = PauseAiCa.Accounts.Scope.for_user(admin)
    {:ok, group} = PauseAiCa.Volunteers.create_group(scope, %{name: "Staging test"})
    {:ok, assignment} = PauseAiCa.Volunteers.assign_manager(scope, group.id, actor.email)
    assert {:ok, prepared} = MailSafety.prepare(message(), admin_actor_id: actor.id)
    assert prepared.to == [{"Staging admin", actor.email}]

    assert {:ok, _} =
             PauseAiCa.Accounts.deliver_login_instructions(actor, fn _ ->
               "http://localhost/sign-in"
             end)

    assert_receive {:email, login}
    assert login.to == [{"Staging sign-in", actor.email}]
    :ok = PauseAiCa.Volunteers.revoke_manager(scope, assignment.id)

    assert {:error, :staging_admin_required} =
             MailSafety.prepare(message(), admin_actor_id: actor.id)
  end

  test "STAGE-AUTH-01 explicit reviewer whitelist allows authentication only, with fresh revocation",
       %{admin: admin} do
    actor =
      unconfirmed_user_fixture()
      |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    scope = PauseAiCa.Accounts.Scope.for_user(admin)

    assert {:error, :staging_admin_required} =
             PauseAiCa.Accounts.deliver_login_instructions(actor, fn _ ->
               "http://localhost/sign-in"
             end)

    assert {:ok, allowed} =
             PauseAiCa.AccountManagement.set_staging_login(scope, actor.email, true)

    refute allowed.superadmin

    assert {:ok, _} =
             PauseAiCa.Accounts.deliver_login_instructions(actor, fn _ ->
               "http://localhost/sign-in"
             end)

    assert_receive {:email, login}
    assert login.to == [{"Staging sign-in", actor.email}]
    assert login.cc == [] and login.bcc == []
    assert {:error, :staging_admin_required} = Mailer.deliver(message(), admin_actor_id: actor.id)

    assert {:error, :staging_admin_required} =
             Mailer.deliver_many([message()], admin_actor_id: actor.id)

    assert {:error, :staging_admin_required} = Mailer.deliver_sign_in(message(), actor.id)
    assert {:ok, _} = PauseAiCa.AccountManagement.set_staging_login(scope, actor.email, false)

    assert {:error, :staging_admin_required} =
             PauseAiCa.Accounts.deliver_login_instructions(actor, fn _ ->
               "http://localhost/sign-in"
             end)

    refute_receive {:email, _}
  end

  test "whitelist changes require a current superadmin, confirmed account and staging", %{
    admin: admin
  } do
    scope = PauseAiCa.Accounts.Scope.for_user(admin)
    pending = unconfirmed_user_fixture()

    assert {:error, :confirmed_account_required} =
             PauseAiCa.AccountManagement.set_staging_login(scope, pending.email, true)

    assert {:error, :confirmed_account_required} =
             PauseAiCa.AccountManagement.set_staging_login(scope, "missing@example.org", true)

    actor =
      unconfirmed_user_fixture()
      |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    assert {:error, :unauthorized} =
             PauseAiCa.AccountManagement.set_staging_login(
               PauseAiCa.Accounts.Scope.for_user(actor),
               actor.email,
               true
             )

    Application.put_env(:pauseai_ca, :mail_environment, :production)

    assert {:error, :unauthorized} =
             PauseAiCa.AccountManagement.set_staging_login(scope, actor.email, true)

    refute Repo.get!(PauseAiCa.Accounts.User, actor.id).staging_login_allowed
  end
end
