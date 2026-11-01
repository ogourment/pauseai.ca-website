defmodule PauseAiCa.InteracDonationsTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.{Accounts, Donations, Newsletters}
  alias PauseAiCa.Donations.{Interac, InteracDeclaration}

  defp attrs(overrides \\ %{}),
    do:
      Map.merge(
        %{
          "name" => "Synthetic transfer sender",
          "email" => "transfer@example.org",
          "amount" => "25.50"
        },
        overrides
      )

  defp submit(overrides \\ %{}), do: Interac.submit(nil, attrs(overrides), Ecto.UUID.generate())

  defp admin do
    user_fixture() |> change(superadmin: true) |> Repo.update!() |> Scope.for_user()
  end

  defp received(overrides \\ %{}),
    do:
      Map.merge(
        %{
          "received_amount" => "25.50",
          "received_on" => Date.to_iso8601(Date.utc_today()),
          "bank_reference" => "BANK-REVIEW-1",
          "verification_note" => "Synthetic bank statement context"
        },
        overrides
      )

  test "guest declaration stays private and pending, defaults anonymous and never infers an account from email" do
    existing = user_fixture()

    before = %{
      accounts: Repo.aggregate(Accounts.User, :count),
      subscriptions: Repo.aggregate(Newsletters.Subscription, :count),
      pledges: Repo.aggregate(Donations.Pledge, :count)
    }

    assert_receive {:email, _}

    assert {:ok, record} =
             submit(%{
               "email" => existing.email,
               "state" => "verified",
               "amount_minor" => "999999",
               "received_minor" => "999999",
               "account_ref" => existing.id,
               "anonymous" => "true"
             })

    assert record.account_ref == nil
    assert record.state == "pending"
    assert record.submitted_actor_id == "public"
    assert record.anonymous
    assert record.amount_minor == 2550
    assert record.received_minor == nil
    assert PhoenixDonations.Declarations.verified_money(record) == nil
    assert {:error, :unauthorized} = Interac.get(Scope.for_user(existing), record.id)

    assert before == %{
             accounts: Repo.aggregate(Accounts.User, :count),
             subscriptions: Repo.aggregate(Newsletters.Subscription, :count),
             pledges: Repo.aggregate(Donations.Pledge, :count)
           }

    refute_receive {:email, _}
  end

  test "signed-in linkage uses the fresh account and retains the declared bank-transfer name" do
    user = user_fixture() |> change(name: "Account owner") |> Repo.update!()
    scope = Scope.for_user(user)
    user |> change(email: "fresh-account@example.org") |> Repo.update!()

    assert {:ok, record} =
             Interac.submit(
               scope,
               attrs(%{
                 "email" => "forged@example.org",
                 "name" => "Name shown on bank transfer",
                 "account_ref" => Ecto.UUID.generate(),
                 "anonymous" => "false"
               }),
               Ecto.UUID.generate()
             )

    assert record.account_ref == user.id
    assert record.email == "fresh-account@example.org"
    assert record.name == "Name shown on bank transfer"
    assert record.submitted_actor_id == user.id
    refute record.anonymous
  end

  test "missing identity and invalid amounts return field errors without persisting" do
    for changes <- [
          %{"name" => ""},
          %{"email" => ""},
          %{"amount" => "0"},
          %{"amount" => "1.001"},
          %{"amount" => "1e3"}
        ] do
      assert {:error, %Ecto.Changeset{valid?: false}} = submit(changes)
    end

    assert Repo.aggregate(InteracDeclaration, :count) == 0
  end

  test "the existing website honeypot convention records no declaration" do
    assert {:ok, :recorded} = submit(%{"website" => "spam.example"})
    assert Repo.aggregate(InteracDeclaration, :count) == 0
  end

  test "stable submission nonce prevents duplicate declarations and changed-payload replay" do
    key = Ecto.UUID.generate()
    assert {:ok, first} = Interac.submit(nil, attrs(), key)
    assert {:ok, replay} = Interac.submit(nil, attrs(), key)
    assert first.id == replay.id
    assert {:error, :submission_conflict} = Interac.submit(nil, attrs(%{"amount" => "50"}), key)
    assert Repo.aggregate(InteracDeclaration, :count) == 1
  end

  test "bounded address submission allowance still permits exact replay at the limit" do
    key = Ecto.UUID.generate()
    assert {:ok, first} = Interac.submit(nil, attrs(), key)
    for _ <- 1..4, do: assert({:ok, _} = submit())
    assert {:error, :rate_limited} = submit()
    assert {:ok, replay} = Interac.submit(nil, attrs(), key)
    assert replay.id == first.id
    assert Repo.aggregate(InteracDeclaration, :count) == 5
  end

  test "fresh superadmin matches actual bank evidence with immutable attribution and separate received totals" do
    scope = admin()
    assert {:ok, record} = submit()
    assert {:ok, %{pending: 1, verified: 0, received_minor: 0}} = Interac.summary(scope)

    assert {:ok, verified} =
             Interac.verify(
               scope,
               record.id,
               received(%{"received_amount" => "30.25"}),
               record.revision
             )

    assert verified.state == "verified"
    assert verified.amount_minor == 2550
    assert verified.received_minor == 3025
    assert verified.verified_actor_id == scope.user.id
    assert verified.verification_note == "Synthetic bank statement context"
    assert {:ok, %{pending: 0, verified: 1, received_minor: 3025}} = Interac.summary(scope)
    assert {:error, :stale} = Interac.verify(scope, record.id, received(), record.revision)

    assert {:error, :already_verified} =
             Interac.verify(scope, record.id, received(), verified.revision)

    assert {:ok, replay} =
             Interac.verify(
               scope,
               record.id,
               received(%{"received_amount" => "30.25"}),
               verified.revision
             )

    assert replay.verified_at == verified.verified_at
    assert replay.verified_actor_id == verified.verified_actor_id
    scope.user |> change(superadmin: false) |> Repo.update!()

    assert {:error, :unauthorized} =
             Interac.verify(scope, record.id, received(), verified.revision)

    assert {:error, :unauthorized} = Interac.list(scope)
  end

  test "one provided bank reference cannot credit two declarations; absent references remain explicit" do
    scope = admin()
    assert {:ok, first} = submit()
    assert {:ok, second} = submit(%{"email" => "other@example.org"})

    assert {:ok, _} =
             Interac.verify(
               scope,
               first.id,
               received(%{"bank_reference" => "  bank-reference-a  "}),
               first.revision
             )

    assert {:error, %Ecto.Changeset{} = duplicate} =
             Interac.verify(
               scope,
               second.id,
               received(%{"bank_reference" => "bank-REFERENCE-A"}),
               second.revision
             )

    assert errors_on(duplicate).bank_reference != []
    assert Repo.get!(InteracDeclaration, second.id).state == "pending"

    assert {:ok, no_reference} =
             Interac.verify(
               scope,
               second.id,
               received(%{"bank_reference" => ""}),
               second.revision
             )

    assert is_nil(no_reference.bank_reference)
    assert no_reference.verification_note == "Synthetic bank statement context"
  end
end
