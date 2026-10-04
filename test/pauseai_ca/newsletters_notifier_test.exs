defmodule PauseAiCa.NewslettersNotifierTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Mailer, Newsletters}
  alias PauseAiCa.Newsletters.Notifier

  setup do
    previous = Application.fetch_env!(:pauseai_ca, :mail_environment)
    on_exit(fn -> Application.put_env(:pauseai_ca, :mail_environment, previous) end)
    :ok
  end

  test "confirmation uses the shared layout; building and provider rejection preserve pending consent" do
    before_accounts = Repo.aggregate(Accounts.User, :count)
    {:ok, request} = Newsletters.request_signup("subscriber@example.org", %{consent: true})
    url = "https://example.org/newsletters/confirm/" <> request.confirmation_token
    email = Notifier.confirmation(request.subscription, url)
    assert email.to == [{"", "subscriber@example.org"}]
    assert email.text_body =~ url
    assert email.html_body =~ url
    assert email.text_body =~ "24 hours"
    assert email.text_body =~ "24 heures"
    Application.put_env(:pauseai_ca, :mail_environment, :blocked)
    assert {:error, :mail_environment_blocked} = Mailer.deliver(email)
    refute Newsletters.eligible?(request.subscription.email)
    assert Repo.get!(Newsletters.Subscription, request.subscription.id).state == "pending"
    assert Repo.aggregate(Accounts.User, :count) == before_accounts
  end

  test "newsletter confirmation cannot use the authentication whitelist staging exception" do
    {:ok, request} = Newsletters.request_signup("subscriber@example.org", %{consent: true})
    email = Notifier.confirmation(request.subscription, "https://example.org/confirmation")
    actor = user_fixture() |> change(superadmin: true) |> Repo.update!()
    Application.put_env(:pauseai_ca, :mail_environment, :staging)
    assert {:error, :staging_admin_required} = Mailer.deliver(email)
    assert {:ok, prepared} = PauseAiCa.MailSafety.prepare(email, admin_actor_id: actor.id)
    assert prepared.to == [{"Staging admin", actor.email}]
    assert prepared.cc == []
    assert prepared.bcc == []
    refute Newsletters.eligible?(request.subscription.email)
    actor |> change(superadmin: false) |> Repo.update!()
    assert {:error, :staging_admin_required} = Mailer.deliver(email, admin_actor_id: actor.id)
  end
end
