defmodule PauseAiCa.Accounts.OnboardingTest do
  use PauseAiCa.DataCase, async: true
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts.{Onboarding, User}

  test "new email creates one pending account with first-touch source" do
    email = unique_user_email()
    context = Onboarding.context(%{"from" => "questions", "locale" => "fr", "risk" => "4"}, nil)

    assert {:ok, user, true, flow} =
             Onboarding.request(email, context, &"https://example.org/#{&1}?flow=#{&2}")

    assert user.signup_entry_point == "home_questions"
    assert is_nil(user.confirmed_at)
    assert user.belief_answers == %{}
    assert Onboarding.restore(flow, user)["answers"] == %{"risk" => "4"}

    assert {:ok, same, false, _} =
             Onboarding.request(email, context, &"https://example.org/#{&1}?flow=#{&2}")

    assert same.id == user.id
  end

  test "existing account is not changed before proof of email ownership" do
    user = user_fixture()

    context =
      Onboarding.context(
        %{"bookmark" => "risk", "from" => "forged", "return_to" => "https://evil.example"},
        nil
      )

    assert {:ok, same, false, flow} =
             Onboarding.request(user.email, context, &"https://example.org/#{&1}?flow=#{&2}")

    assert same.id == user.id
    assert Repo.get!(User, user.id).saved_resources == []
    assert Onboarding.restore(flow, user)["return_to"] == "/en/learn"
    assert Onboarding.restore(flow, user_fixture()) == %{}
    assert Onboarding.restore(flow <> "tampered", user) == %{}
  end

  test "invalid email preserves domain validation instead of creating an account" do
    assert {:error, %Ecto.Changeset{valid?: false}} =
             Onboarding.request("with spaces", %{}, &"https://example.org/#{&1}?flow=#{&2}")
  end

  test "resend cannot rebind an encrypted task to another address or its visitor history" do
    first = unique_user_email()
    context = Onboarding.context(%{"from" => "questions", "risk" => "4"}, Ecto.UUID.generate())

    assert {:ok, owner, true, flow} =
             Onboarding.request(first, context, &"https://example.org/#{&1}?flow=#{&2}")

    assert {:error, :continuation} =
             Onboarding.request(
               unique_user_email(),
               Onboarding.decode(flow),
               &"https://example.org/#{&1}?flow=#{&2}"
             )

    assert Repo.aggregate(User, :count) == 1

    assert {:ok, same, false, _} =
             Onboarding.request(
               first,
               Onboarding.decode(flow),
               &"https://example.org/#{&1}?flow=#{&2}"
             )

    assert same.id == owner.id
  end

  test "creation source cannot be mass-assigned and database rejects unrecognized sources" do
    assert {:ok, user} =
             PauseAiCa.Accounts.register_user(%{
               email: unique_user_email(),
               signup_entry_point: "header"
             })

    assert user.signup_entry_point == nil

    assert_raise Ecto.ConstraintError, fn ->
      PauseAiCa.Accounts.register_user(%{email: unique_user_email()},
        signup_entry_point: "forged"
      )
    end
  end
end
