defmodule PauseAiCa.NewslettersTest do
  use PauseAiCa.DataCase, async: true
  alias PauseAiCa.{Newsletters, Accounts}
  alias PauseAiCa.Newsletters.{Subscription, ConsentEvent}
  import PauseAiCa.AccountsFixtures

  test "explicit signup survives provider unavailability; confirmation is single use; no account or mail effects" do
    accounts = Repo.aggregate(Accounts.User, :count)
    assert {:error, :consent_required} = Newsletters.request_signup("newsletter@example.org", %{})
    assert Repo.aggregate(Subscription, :count) == 0

    assert {:ok, request} =
             Newsletters.request_signup(" Newsletter@EXAMPLE.org ", %{
               consent: true,
               locale: "fr",
               city: "Montréal"
             })

    assert request.subscription.email == "newsletter@example.org"
    assert request.subscription.state == "pending"
    refute Newsletters.eligible?(request.subscription.email)
    refute request.subscription.confirmation_hash == request.confirmation_token
    assert {:ok, confirmed} = Newsletters.confirm(request.confirmation_token)
    assert confirmed.state == "confirmed"
    assert confirmed.confirmed_at
    assert Newsletters.eligible?(confirmed.email)
    assert {:error, :invalid_token} = Newsletters.confirm(request.confirmation_token)
    assert {:ok, same} = Newsletters.request_signup(confirmed.email, %{consent: true})
    assert same.confirmation_token == nil
    assert same.subscription.confirmed_at == confirmed.confirmed_at
    assert Repo.aggregate(Accounts.User, :count) == accounts
    assert Repo.aggregate(ConsentEvent, :count) == 2
  end

  test "withdrawal blocks pending confirmation, survives repeat requests, and needs a fresh explicit confirmation" do
    {:ok, first} = Newsletters.request_signup("withdraw@example.org", %{consent: true})
    assert {:ok, withdrawn} = Newsletters.withdraw(first.withdrawal_token)
    assert withdrawn.state == "withdrawn"
    assert {:error, :invalid_token} = Newsletters.confirm(first.confirmation_token)
    assert {:ok, ^withdrawn} = Newsletters.withdraw(first.withdrawal_token)
    {:ok, retry} = Newsletters.request_signup(withdrawn.email, %{consent: true})
    assert retry.subscription.withdrawn_at == withdrawn.withdrawn_at
    refute Newsletters.eligible?(withdrawn.email)
    assert {:ok, _} = Newsletters.confirm(retry.confirmation_token)
    assert Newsletters.eligible?(withdrawn.email)
    assert Repo.aggregate(ConsentEvent, :count) == 4
    assert {:ok, _} = Newsletters.withdraw(first.withdrawal_token)
    refute Newsletters.eligible?(withdrawn.email)
    assert Repo.aggregate(ConsentEvent, :count) == 5
  end

  test "expired and replaced confirmation tokens cannot grant eligibility" do
    {:ok, first} = Newsletters.request_signup("expire@example.org", %{consent: true})
    {:ok, second} = Newsletters.request_signup("expire@example.org", %{consent: true})
    assert {:error, :invalid_token} = Newsletters.confirm(first.confirmation_token)

    second.subscription
    |> change(confirmation_expires_at: DateTime.add(DateTime.utc_now(), -1))
    |> Repo.update!()

    assert {:error, :invalid_token} = Newsletters.confirm(second.confirmation_token)
    refute Newsletters.eligible?(first.subscription.email)
    assert {:error, :invalid_token} = Newsletters.confirm("bad")
  end

  test "legacy membership remains review-only; fresh role revocation prevents observations and access" do
    user = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = PauseAiCa.Accounts.Scope.for_user(user)

    assert {:ok, legacy} =
             Newsletters.observe_legacy(scope, "legacy@example.org", %{
               "provider" => "brevo",
               "list_id" => 2
             })

    assert legacy.state == "legacy_review"
    assert is_nil(legacy.confirmed_at)
    assert is_nil(legacy.requested_at)
    refute Newsletters.eligible?(legacy.email)
    assert {:ok, [_]} = Newsletters.history(scope, legacy.id)
    {:ok, request} = Newsletters.request_signup(legacy.email, %{consent: true})
    {:ok, confirmed} = Newsletters.confirm(request.confirmation_token)

    assert {:ok, observed} =
             Newsletters.observe_legacy(scope, legacy.email, %{"membership" => true})

    assert observed.confirmed_at == confirmed.confirmed_at
    assert observed.state == "confirmed"
    user |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Newsletters.observe_legacy(scope, "other@example.org", %{})
    assert {:error, :unauthorized} = Newsletters.history(scope, legacy.id)
    assert {:error, :unauthorized} = Newsletters.audience(scope)
    assert Repo.aggregate(Subscription, :count) == 1
  end

  test "withdrawals on linked addresses and historical origins block alternate-address newsletter delivery" do
    person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic subscriber"})
    Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: "primary@example.org"})
    Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: "alternate@example.org"})
    {:ok, primary} = Newsletters.request_signup("primary@example.org", %{consent: true})
    {:ok, alternate} = Newsletters.request_signup("alternate@example.org", %{consent: true})
    Newsletters.confirm(primary.confirmation_token)
    Newsletters.confirm(alternate.confirmation_token)
    assert Newsletters.eligible?("alternate@example.org")
    Newsletters.withdraw(primary.withdrawal_token)
    refute Newsletters.eligible?("alternate@example.org")
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = PauseAiCa.Accounts.Scope.for_user(admin)
    assert {:ok, withheld} = Newsletters.audience_page(scope, %{})
    assert withheld.counts.withdrawn == 1
    assert withheld.counts.suppressed == 1
    assert withheld.counts.included == 0
    {:ok, fresh} = Newsletters.request_signup("primary@example.org", %{consent: true})
    Newsletters.confirm(fresh.confirmation_token)

    contact =
      Repo.insert!(%PauseAiCa.ContactMigration.Contact{
        email: "historical@example.org",
        classification: "do_not_contact",
        source: "synthetic",
        source_key: "synthetic:withdrawal",
        source_data: %{}
      })

    Repo.insert!(%PauseAiCa.CRM.ContactLink{contact_id: contact.id, person_id: person.id})
    refute Newsletters.eligible?("primary@example.org")
    refute Newsletters.eligible?("alternate@example.org")
    assert {:ok, blocked} = Newsletters.audience_page(scope, %{})
    assert blocked.counts.suppressed == 2
    assert blocked.counts.included == 0
  end

  test "provider observations exclude delivery without granting consent and retain chronological attribution" do
    user = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = PauseAiCa.Accounts.Scope.for_user(user)

    evidence = %{
      "provider_id" => 42,
      "observed_at" => "2026-10-04T12:00:00Z",
      "email_blacklisted" => true
    }

    assert {:ok, legacy} = Newsletters.observe_provider(scope, "blocked@example.org", evidence)
    assert legacy.state == "legacy_review"
    refute Newsletters.eligible?(legacy.email)

    {:ok, request} =
      Newsletters.request_signup(legacy.email, %{consent: true, region: "Montréal"})

    {:ok, _} = Newsletters.confirm(request.confirmation_token)
    refute Newsletters.eligible?(legacy.email)
    # An older provider result arriving later must not lift the suppression.
    assert {:ok, _} =
             Newsletters.observe_provider(scope, legacy.email, %{
               evidence
               | "observed_at" => "2026-10-03T12:00:00Z",
                 "email_blacklisted" => false
             })

    assert Newsletters.provider_blocked?(legacy.email)
    assert {:ok, page} = Newsletters.audience_page(scope, %{"region" => "Montréal"})
    assert page.counts.provider_blocked == 1
    assert page.counts.included == 0

    assert {:ok, _} =
             Newsletters.observe_provider(scope, legacy.email, %{
               evidence
               | "observed_at" => "2026-10-04T13:00:00Z",
                 "email_blacklisted" => false
             })

    assert Newsletters.eligible?(legacy.email)
    assert {:ok, events} = Newsletters.history(scope, legacy.id)

    assert Enum.filter(events, &(&1.kind == "provider_observed"))
           |> Enum.all?(&(&1.actor_id == user.id))

    assert {:error, :invalid_observation} =
             Newsletters.observe_provider(scope, legacy.email, %{"observed_at" => 1})

    user |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Newsletters.observe_provider(scope, legacy.email, evidence)
    assert {:error, :unauthorized} = Newsletters.audience_page(scope, %{})
  end

  test "audience geography, exclusions and page position have no account or consent effects" do
    user = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = PauseAiCa.Accounts.Scope.for_user(user)
    accounts = Repo.aggregate(Accounts.User, :count)

    for n <- 1..11 do
      email = "member#{String.pad_leading(to_string(n), 2, "0")}@example.org"
      {:ok, _} = Newsletters.request_signup(email, %{consent: true, region: "Montréal"})
    end

    {:ok, _} =
      Newsletters.request_signup("elsewhere@example.org", %{consent: true, region: "ROCanada"})

    events = Repo.aggregate(ConsentEvent, :count)

    assert {:ok, first} =
             Newsletters.audience_page(scope, %{"region" => "Montréal", "per" => "10"})

    assert first.total == 11
    assert first.counts.unconfirmed == 11
    assert length(first.rows) == 10

    assert {:ok, last} =
             Newsletters.audience_page(scope, %{
               "region" => "Montréal",
               "per" => "10",
               "page" => "99"
             })

    assert last.page == 2
    assert length(last.rows) == 1
    assert {:ok, empty} = Newsletters.audience_page(scope, %{"q" => "no-match"})
    assert empty.total == 0
    assert empty.page == 1
    assert Repo.aggregate(ConsentEvent, :count) == events
    assert Repo.aggregate(Accounts.User, :count) == accounts
  end
end
