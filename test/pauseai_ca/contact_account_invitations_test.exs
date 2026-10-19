defmodule PauseAiCa.ContactAccountInvitationsTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters}
  alias PauseAiCa.Newsletters.{Draft, Drafts, Batches, Batch, Delivery, Edition}

  setup do
    actor = user_fixture() |> change(superadmin: true) |> Repo.update!()
    flush_emails()
    %{scope: Accounts.Scope.for_user(actor)}
  end

  test "personalized multiselection creates disjoint language drafts, excludes withdrawals and sends only after review and approval",
       %{scope: scope} do
    people =
      for {suffix, language} <- [
            {"en", "en"},
            {"fr", "fr"},
            {"unknown", "unknown"},
            {"withdrawn", "en"}
          ] do
        person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic invitation #{suffix}"})
        email = "invite-#{suffix}@example.org"
        Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: email})
        {:ok, _} = Edition.confirm_preference(scope, email, language)
        person
      end

    {:ok, signup} =
      Newsletters.request_signup("invite-withdrawn@example.org", %{consent: true, locale: "en"})

    {:ok, _} = Newsletters.withdraw(signup.withdrawal_token)
    users = Repo.aggregate(Accounts.User, :count)
    subscriptions = Repo.aggregate(Newsletters.Subscription, :count)

    attrs = %{
      "inviter" => "Olivier Gourment",
      "reason_en" => "We met at the Montréal event. You offered to help with local activities.",
      "reason_fr" =>
        "Nous nous sommes rencontrés à Montréal. Vous avez proposé votre aide pour les activités locales."
    }

    assert {:ok, result} =
             Drafts.create_account_invitations(scope, Enum.map(people, & &1.id), attrs)

    assert result.included == 3
    assert [%{email: "invite-withdrawn@example.org"}] = result.excluded
    drafts = Map.new(result.drafts, &{&1.edition, &1})
    assert Enum.sort(Map.keys(drafts)) == ["en", "fr", "unknown"]
    assert Enum.all?(result.drafts, &(length(&1.recipient_keys) == 1))
    assert length(Enum.uniq(Enum.flat_map(result.drafts, & &1.recipient_keys))) == 3
    assert drafts["en"].source =~ attrs["reason_en"]
    refute drafts["en"].source =~ attrs["reason_fr"]
    assert drafts["fr"].source =~ attrs["reason_fr"]
    refute drafts["fr"].source =~ attrs["reason_en"]
    assert drafts["unknown"].source =~ attrs["reason_en"]
    assert drafts["unknown"].source =~ attrs["reason_fr"]
    assert Enum.all?(result.drafts, &(&1.source =~ "Olivier Gourment"))
    assert Repo.aggregate(Accounts.User, :count) == users
    assert Repo.aggregate(Newsletters.Subscription, :count) == subscriptions
    assert Repo.aggregate(Batch, :count) == 0
    assert Repo.aggregate(Delivery, :count) == 0
    refute_receive {:email, _}

    draft = drafts["en"]

    assert {:error, :review_required} =
             Batches.prepare(scope, draft, "contacts", draft.recipient_keys, false)

    assert {:ok, batch} = Batches.prepare(scope, draft, "contacts", draft.recipient_keys, true)
    assert {:ok, :not_approved} = Batches.dispatch(scope, batch.id)
    refute_receive {:email, _}
    assert {:ok, _} = Batches.approve(scope, batch.id)
    assert {:ok, :completed} = Batches.dispatch(scope, batch.id)
    assert_receive {:email, email}
    assert email.to == [{"", "invite-en@example.org"}]
    assert email.text_body =~ attrs["reason_en"]
    assert email.text_body =~ "Olivier Gourment"
    assert email.text_body =~ "/users/register?locale=en"
    assert Repo.aggregate(Accounts.User, :count) == users

    assert Repo.aggregate(
             from(s in Newsletters.Subscription, where: s.state == "confirmed"),
             :count
           ) == 0
  end

  test "missing context or unavailable contacts cannot create partial drafts, and actor authority is rechecked",
       %{scope: scope} do
    person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic recipient"})
    Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: "invite-context@example.org"})

    assert {:error, :invitation_context_required} =
             Drafts.create_account_invitations(scope, [person.id], %{"inviter" => "Olivier"})

    assert Repo.aggregate(Draft, :count) == 0
    assert {:error, _} = Drafts.create_account_invitations(scope, [Ecto.UUID.generate()], %{})
    assert Repo.aggregate(Draft, :count) == 0
    scope.user |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Drafts.create_account_invitations(scope, [person.id], %{})
  end

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
