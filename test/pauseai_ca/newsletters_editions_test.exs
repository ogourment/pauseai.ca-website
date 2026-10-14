defmodule PauseAiCa.NewslettersEditionsTest do
  use PauseAiCa.DataCase
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters}
  alias PauseAiCa.Newsletters.{Batches, Drafts, Edition, ConsentEvent}

  test "only evidenced language enters its edition; ambiguous or default-only stays unknown" do
    assert Edition.recorded(%{"languages" => "French"}) == "fr"
    assert Edition.recorded(%{"languages" => "English, French"}) == "unknown"
    assert Edition.recorded(%{"city" => "Montréal"}) == "unknown"

    assert Edition.recorded([
             %{"languages" => "English"},
             %{"languages" => ["English", "French"]}
           ]) == "unknown"

    for {address, attrs} <- [
          {"en@example.org", %{locale: "en"}},
          {"fr@example.org", %{locale: "fr"}},
          {"unknown@example.org", %{}}
        ] do
      {:ok, request} = Newsletters.request_signup(address, Map.merge(%{consent: true}, attrs))
      {:ok, _} = Newsletters.confirm(request.confirmation_token)
    end

    rows =
      Enum.map(["en", "fr", "unknown"], &%{email: &1 <> "@example.org"}) |> Edition.decorate()

    assert Enum.map(rows, & &1.edition) == ["en", "fr", "unknown"]
  end

  test "whole-list edition, locale envelope and language drift are enforced at delivery" do
    actor = user_fixture() |> change(superadmin: true) |> Repo.update!()
    flush_emails()
    scope = Accounts.Scope.for_user(actor)

    {:ok, list} =
      Newsletters.Lists.save(scope, nil, %{
        "name" => "Local",
        "match" => "any",
        "city" => "Toronto",
        "region" => "",
        "fsas" => ""
      })

    for {address, locale} <- [{"en@example.org", "en"}, {"fr@example.org", "fr"}] do
      {:ok, request} =
        Newsletters.request_signup(address, %{consent: true, locale: locale, city: "Toronto"})

      {:ok, _} = Newsletters.confirm(request.confirmation_token)
    end

    {:ok, draft} = Drafts.create_for_list(scope, list.id)

    {:ok, draft} =
      Drafts.save(scope, draft, %{
        "edition" => "fr",
        "subject" => "Actualités",
        "source" => "Bonjour"
      })

    {:ok, audience} = Batches.audience(scope, "list", %{"list_id" => list.id, "edition" => "fr"})
    assert audience.total == 1
    assert audience.edition_counts == %{"en" => 1, "fr" => 1}
    {:ok, batch} = Batches.prepare(scope, draft, "list", [], false)
    assert length(batch.recipient_keys) == 1
    {:ok, _} = Batches.approve(scope, batch.id)
    sub = Repo.get_by!(Newsletters.Subscription, email: "fr@example.org")

    Repo.insert!(%ConsentEvent{
      subscription_id: sub.id,
      kind: "language_preference",
      evidence: %{"locale" => "en"},
      inserted_at: DateTime.add(DateTime.utc_now(), 1)
    })

    assert {:ok, :stale} = Batches.dispatch(scope, batch.id)
    refute_receive {:email, _}
  end

  test "an unfinished final Markdown URL cannot prepare a batch" do
    actor = user_fixture() |> change(superadmin: true) |> Repo.update!()
    flush_emails()
    scope = Accounts.Scope.for_user(actor)
    {:ok, draft} = Drafts.create(scope)

    {:ok, draft} =
      Drafts.save(scope, draft, %{
        "subject" => "News",
        "source" => "Visit our [**website**](https"
      })

    assert {:error, :incomplete_link} = Batches.prepare(scope, draft, "contacts", [], true)

    assert PauseAiCa.Mail.Render.complete_links?(
             "Visit our [**website**](https://pauseai.ca/fr)."
           )
  end

  test "English, French and fallback batches deliver disjoint language editions" do
    actor = user_fixture() |> change(superadmin: true) |> Repo.update!()
    flush_emails()
    scope = Accounts.Scope.for_user(actor)

    subscriptions =
      for language <- ["en", "fr", "unknown"] do
        attrs =
          if language == "unknown", do: %{consent: true}, else: %{consent: true, locale: language}

        {:ok, request} = Newsletters.request_signup(language <> "@example.org", attrs)
        {:ok, subscription} = Newsletters.confirm(request.confirmation_token)
        subscription
      end

    for language <- ["en", "fr", "unknown"] do
      {:ok, draft} = Drafts.create(scope)

      {:ok, draft} =
        Drafts.save(scope, draft, %{
          "edition" => language,
          "subject" => "Updates",
          "source" => "Complete [website](https://pauseai.ca)"
        })

      {:ok, batch} =
        Batches.prepare(scope, draft, "newsletter", Enum.map(subscriptions, & &1.id), false)

      assert length(batch.recipient_keys) == 1
      {:ok, _} = Batches.approve(scope, batch.id)
      assert {:ok, :completed} = Batches.dispatch(scope, batch.id)
      assert_receive {:email, email}
      assert email.to == [{"", language <> "@example.org"}]
      assert String.contains?(email.html_body, "You are receiving") == (language != "fr")
      assert String.contains?(email.html_body, "Vous recevez") == (language != "en")
      refute_receive {:email, _}
    end
  end

  test "verified preferences are attributed, override source evidence and require a fresh role" do
    actor = user_fixture() |> change(superadmin: true) |> Repo.update!()
    flush_emails()
    scope = Accounts.Scope.for_user(actor)
    before_accounts = Repo.aggregate(Accounts.User, :count)
    before_subscriptions = Repo.aggregate(Newsletters.Subscription, :count)
    assert {:ok, preference} = Edition.confirm_preference(scope, "person@example.org", "fr")
    assert preference.actor_id == actor.id
    assert [%{edition: "fr"}] = Edition.decorate([%{email: "person@example.org"}])
    assert Repo.aggregate(Accounts.User, :count) == before_accounts
    assert Repo.aggregate(Newsletters.Subscription, :count) == before_subscriptions
    actor |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Edition.confirm_preference(scope, "person@example.org", "en")
    refute_receive {:email, _}
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
