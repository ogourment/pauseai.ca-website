defmodule PauseAiCa.NewslettersSignupTest do
  use PauseAiCa.DataCase, async: false
  import Ecto.Query
  alias PauseAiCa.{Newsletters, Accounts}
  alias PauseAiCa.Newsletters.{Signup, Subscription, ConsentEvent}

  setup do
    previous = Application.fetch_env!(:pauseai_ca, :mail_environment)
    on_exit(fn -> Application.put_env(:pauseai_ca, :mail_environment, previous) end)
    :ok
  end

  test "failed confirmation retains opt-in, cooldown survives calls, and retry does not create accounts" do
    accounts = Repo.aggregate(Accounts.User, :count)
    Application.put_env(:pauseai_ca, :mail_environment, :blocked)
    attrs = %{consent: true, locale: "fr"}
    url = &"https://example.org/newsletters/confirm/#{&1}"
    assert {:error, :confirmation_unavailable} = Signup.request("pending@example.org", attrs, url)
    subscription = Repo.get_by!(Subscription, email: "pending@example.org")
    assert subscription.state == "pending"
    refute Newsletters.eligible?(subscription.email)
    assert {:error, :confirmation_unavailable} = Signup.request("pending@example.org", attrs, url)
    assert Repo.aggregate(ConsentEvent, :count) == 3
    assert {:error, :consent_required} = Signup.request("pending@example.org", %{}, url)

    Repo.update_all(from(e in ConsentEvent, where: e.kind == "confirmation_attempted"),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -61)]
    )

    Application.put_env(:pauseai_ca, :mail_environment, :test)
    assert {:ok, :pending_confirmation} = Signup.request("pending@example.org", attrs, url)
    assert Repo.aggregate(Subscription, :count) == 1
    assert Repo.aggregate(Accounts.User, :count) == accounts

    assert Repo.exists?(
             from e in ConsentEvent,
               where:
                 e.kind == "confirmation_delivery" and
                   fragment("?->>'status'", e.evidence) == "accepted"
           )
  end

  test "durable global confirmation quota refuses a new address before creating or delivering anything" do
    Application.put_env(:pauseai_ca, :mail_environment, :blocked)
    attrs = %{consent: true}
    url = &"https://example.org/newsletters/confirm?token=#{&1}"
    assert {:error, :confirmation_unavailable} = Signup.request("quota@example.org", attrs, url)
    subscription = Repo.get_by!(Subscription, email: "quota@example.org")

    rows =
      for _ <- 1..99 do
        %{
          id: Ecto.UUID.generate(),
          subscription_id: subscription.id,
          kind: "confirmation_attempted",
          evidence: %{},
          inserted_at: DateTime.utc_now()
        }
      end

    Repo.insert_all(ConsentEvent, rows)
    assert {:error, :confirmation_unavailable} = Signup.request("excess@example.org", attrs, url)
    refute Repo.get_by(Subscription, email: "excess@example.org")
    assert Repo.aggregate(Subscription, :count) == 1
    assert Repo.aggregate(ConsentEvent, :count) == 102
  end
end
