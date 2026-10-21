defmodule PauseAiCa.ParticipationTest do
  use PauseAiCa.DataCase
  alias PauseAiCa.{Participation, Accounts, Repo, Newsletters}
  alias PauseAiCa.Participation.Request

  defp attrs(extra \\ %{}),
    do:
      Map.merge(
        %{
          "email" => "choices@example.org",
          "name" => "Morgan Example",
          "fsa" => "M5V",
          "city" => "Toronto",
          "locale" => "en",
          "newsletter" => "true",
          "account" => "false"
        },
        extra
      )

  defp context, do: %{"locale" => "en", "source" => "home_footer", "return_to" => "/en/dashboard"}

  defp urls do
    fn
      :account, {token, flow} ->
        "http://localhost/users/log-in/#{token}?" <>
          URI.encode_query(%{"flow" => flow, "locale" => "en"})

      kind, token ->
        "http://localhost/participation/#{kind}?token=#{token}"
    end
  end

  defp token(mail, kind) do
    [_, token] = Regex.run(~r{/participation/#{kind}\?token=([^\s]+)}, mail.text_body)
    token
  end

  test "newsletter and waitlist share one confirmation without creating an account" do
    assert {:ok, :pending} =
             Participation.request(attrs(%{"local_kind" => "waitlist"}), context(), urls())

    assert_receive {:email, mail}
    refute_receive {:email, _}
    refute Accounts.get_user_by_email("choices@example.org")
    refute Repo.exists?(Newsletters.Subscription)
    token = token(mail, "confirm")
    assert {:ok, _} = Participation.capability(token, :confirm)
    assert Repo.one!(Request).state == "pending"
    assert {:ok, confirmed} = Participation.confirm(token)
    assert confirmed.local_kind == "waitlist"
    assert Repo.one!(Newsletters.Subscription).state == "confirmed"
    refute Accounts.get_user_by_email("choices@example.org")
    assert {:error, _} = Participation.confirm(token)
  end

  test "newsletter requires a home area, distinct from the group someone wants to join" do
    assert {:error, c} =
             Participation.request(
               attrs(%{"fsa" => "", "local_kind" => "waitlist"}),
               context(),
               urls()
             )

    assert c.errors[:location]
    refute_receive {:email, _}
    refute Repo.exists?(Request)

    assert {:ok, _} =
             Participation.request(
               attrs(%{"fsa" => "", "location" => "H2X", "local_kind" => "waitlist"}),
               context(),
               urls()
             )

    assert_receive {:email, mail}
    assert {:ok, request} = Participation.confirm(token(mail, "confirm"))
    assert request.fsa == "H2X"
    assert request.city == "Toronto"
    assert Repo.one!(Newsletters.Subscription).fsa == "H2X"
  end

  test "verified edits preserve identity and withdraw deselected purposes only after confirmation" do
    assert {:ok, _} =
             Participation.request(attrs(%{"local_kind" => "waitlist"}), context(), urls())

    assert_receive {:email, mail}
    assert {:ok, original} = Participation.confirm(token(mail, "confirm"))
    edit = Participation.choices_token(original)
    assert {:error, :invalid_choices} = Participation.update_choices("invented", attrs(), urls())

    assert {:ok, _} =
             Participation.update_choices(
               edit,
               attrs(%{
                 "email" => "other@example.org",
                 "newsletter" => "false",
                 "local_kind" => nil
               }),
               urls()
             )

    assert_receive {:email, updated_mail}
    assert updated_mail.to == [{"", original.email}]
    assert Repo.one!(Newsletters.Subscription).state == "confirmed"
    assert Repo.get!(Request, original.id).local_kind == "waitlist"
    assert {:ok, updated} = Participation.confirm(token(updated_mail, "confirm"))
    assert updated.email == original.email
    refute updated.newsletter
    assert is_nil(updated.local_kind)
    assert Repo.one!(Newsletters.Subscription).state == "withdrawn"
    assert is_nil(Repo.get!(Request, original.id).local_kind)
    assert {:error, :invalid_choices} = Participation.choices_request(edit)
  end

  test "expired edit proof cannot issue a new request or email" do
    assert {:ok, _} = Participation.request(attrs(), context(), urls())
    assert_receive {:email, _}
    original = Repo.one!(Request)

    expired =
      Phoenix.Token.encrypt(
        PauseAiCaWeb.Endpoint,
        "participation choices v1",
        {original.id, original.updated_at, original.state},
        signed_at: System.system_time(:second) - 901
      )

    assert {:error, :invalid_choices} = Participation.update_choices(expired, attrs(), urls())
    assert Repo.aggregate(Request, :count) == 1
    refute_receive {:email, _}
  end

  test "editing a pending request invalidates its old confirmation and preserves selected details" do
    assert {:ok, _} = Participation.request(attrs(), context(), urls())
    assert_receive {:email, original_mail}
    original = Repo.one!(Request)
    edit = Participation.choices_token(original)
    assert {:ok, loaded} = Participation.choices_request(edit)
    assert loaded.name == original.name

    assert {:ok, _} =
             Participation.update_choices(edit, attrs(%{"name" => "Updated name"}), urls())

    assert_receive {:email, updated_mail}
    assert {:error, _} = Participation.confirm(token(original_mail, "confirm"))
    assert {:error, _} = Participation.choices_request(edit)
    assert {:ok, changed} = Participation.confirm(token(updated_mail, "confirm"))
    assert changed.name == "Updated name"
  end

  test "a confirmed newsletter signup can explicitly add an account without another email" do
    assert {:ok, _} =
             Participation.request(attrs(), Map.put(context(), "basket", ["risk"]), urls())

    assert_receive {:email, mail}
    pending = Repo.one!(Request)
    assert is_nil(Participation.account_offer(pending))
    assert {:ok, request} = Participation.confirm(token(mail, "confirm"))
    offer = Participation.account_offer(request)
    refute Accounts.get_user_by_email(request.email)

    assert {:ok, user} = Participation.create_account(offer)
    assert user.email == request.email
    assert user.name == request.name
    assert user.fsa == request.fsa
    assert user.confirmed_at
    assert "risk" in user.saved_resources
    refute user.superadmin
    refute_receive {:email, _}
    assert Repo.one!(Newsletters.Subscription).state == "confirmed"
    stored = Repo.get!(Request, request.id)
    refute stored.account
    assert stored.user_id == user.id
    assert stored.context["account_created_after_confirmation_at"]
    assert {:error, :invalid_offer} = Participation.create_account(offer)
    assert Repo.aggregate(Accounts.User, :count) == 1
  end

  test "account offers reject tampering, expiry, changed state and existing accounts" do
    assert {:ok, _} = Participation.request(attrs(), context(), urls())
    assert_receive {:email, mail}
    assert {:ok, request} = Participation.confirm(token(mail, "confirm"))
    offer = Participation.account_offer(request)

    expired =
      Phoenix.Token.encrypt(PauseAiCaWeb.Endpoint, "participation account offer v1", request.id,
        signed_at: System.system_time(:second) - 901
      )

    assert {:error, :invalid_offer} = Participation.create_account(expired)
    assert {:error, :invalid_offer} = Participation.create_account(offer <> "tampered")

    request |> Ecto.Changeset.change(state: "withdrawn") |> Repo.update!()
    assert {:error, :invalid_offer} = Participation.create_account(offer)
    Repo.get!(Request, request.id) |> Ecto.Changeset.change(state: "confirmed") |> Repo.update!()
    {:ok, existing} = Accounts.register_user(%{"email" => request.email})
    assert {:error, :account_exists} = Participation.create_account(offer)
    assert Accounts.get_user!(existing.id) == existing
    assert is_nil(Repo.get!(Request, request.id).user_id)
  end

  test "account plus both purposes uses existing ownership login and applies choices only after POST" do
    assert {:ok, :pending} =
             Participation.request(
               attrs(%{
                 "account" => "true",
                 "phone" => "+1 613 555 0100",
                 "local_kind" => "help",
                 "help_text" => "I can find a venue"
               }),
               context(),
               urls()
             )

    assert_receive {:email, mail}
    refute_receive {:email, _}
    user = Accounts.get_user_by_email("choices@example.org")
    refute user.confirmed_at
    refute user.superadmin
    refute Repo.exists?(Newsletters.Subscription)
    [_, token] = Regex.run(~r{/users/log-in/([^?\s]+)}, mail.text_body)
    [_, flow] = Regex.run(~r{flow=([^&\s]+)}, mail.text_body)
    assert {:ok, {user, _}} = Accounts.login_user_by_magic_link(token)
    context = Accounts.Onboarding.restore(URI.decode_www_form(flow), user)
    assert :ok = Accounts.Onboarding.apply_context(user, context, nil)
    assert Repo.one!(Request).state == "confirmed"
    assert Repo.one!(Newsletters.Subscription).state == "confirmed"
    assert Accounts.get_user!(user.id).name == "Morgan Example"
    assert Accounts.get_user!(user.id).fsa == "M5V"
    assert Accounts.get_user!(user.id).phone == "+1 613 555 0100"
  end

  test "waitlist without other choices sends one link and grants neither subscription nor account" do
    assert {:ok, _} =
             Participation.request(
               attrs(%{"newsletter" => "false", "local_kind" => "waitlist"}),
               context(),
               urls()
             )

    assert_receive {:email, mail}
    assert {:ok, _} = Participation.confirm(token(mail, "confirm"))
    refute Accounts.get_user_by_email("choices@example.org")
    refute Repo.exists?(Newsletters.Subscription)
    assert {:ok, _} = Participation.withdraw(token(mail, "withdraw"))
    assert Repo.one!(Request).withdrawn_at
  end

  test "no selected option and invalid FSA never send or persist" do
    assert {:error, c} =
             Participation.request(attrs(%{"newsletter" => "false"}), context(), urls())

    assert c.errors[:newsletter]
    assert {:error, c} = Participation.request(attrs(%{"fsa" => "123"}), context(), urls())
    assert c.errors[:fsa]
    refute Repo.exists?(Request)
    refute_receive {:email, _}
  end

  test "identical retry is quiet and changed choices within cooldown remain unapplied" do
    assert {:ok, _} = Participation.request(attrs(), context(), urls())
    assert_receive {:email, _}
    assert {:ok, _} = Participation.request(attrs(), context(), urls())
    refute_receive {:email, _}

    assert {:error, :changed_choices_cooldown} =
             Participation.request(attrs(%{"account" => "true"}), context(), urls())

    refute Accounts.get_user_by_email("choices@example.org")
  end

  test "local requests are confirmed-only, paginated and freshly restricted when ownership changes" do
    admin =
      PauseAiCa.AccountsFixtures.user_fixture()
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()

    scope = Accounts.Scope.for_user(admin)
    now = DateTime.utc_now()

    for n <- 1..26 do
      Repo.insert!(%Request{
        email: "local-#{n}@example.org",
        locale: "en",
        state: "confirmed",
        local_kind: "waitlist",
        city: "Toronto",
        confirmed_at: now,
        expires_at: DateTime.add(now, 86400),
        withdrawal_hash: :crypto.hash(:sha256, to_string(n))
      })
    end

    assert {:ok, %{total: 26, pages: 2, entries: first}} = Participation.local_requests(scope)
    assert length(first) == 25
    assert {:ok, %{entries: last}} = Participation.local_requests(scope, 2)
    assert length(last) == 1
    assert {:ok, claimed} = Participation.claim(scope, hd(first).id)
    assert claimed.followup_owner_id == admin.id
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Participation.local_requests(scope)
    assert {:error, :unauthorized} = Participation.claim(scope, hd(last).id)
  end
end
