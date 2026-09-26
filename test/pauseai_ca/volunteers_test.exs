defmodule PauseAiCa.VolunteersTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Volunteers}
  alias PauseAiCa.Accounts.{Scope, User}
  alias PauseAiCa.Volunteers.{Batch, Input, Invitation, Profile, Signup}

  setup do
    admin =
      user_fixture()
      |> change(superadmin: true, confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    scope = Scope.for_user(admin)
    {:ok, montreal} = Volunteers.create_group(scope, %{"name" => "Montréal"})
    {:ok, quebec} = Volunteers.create_group(scope, %{"name" => "Québec"})
    %{scope: scope, montreal: montreal, quebec: quebec}
  end

  test "confirmation creates accounts and a durable intent once; email confirms the account", %{
    scope: scope,
    montreal: group
  } do
    row =
      Input.normalize(%{
        "name" => "Camille",
        "email" => "  CAMILLE@example.org ",
        "postal_code" => "h2x 1y4",
        "notes" => "private note",
        "selected" => true
      })

    {:ok, batch} =
      Volunteers.save_draft(scope, nil, %{"rows" => [row], "default_group_id" => group.id})

    assert Repo.aggregate(Signup, :count) == 0
    assert {:ok, confirmed} = Volunteers.confirm(scope, batch.id)
    assert confirmed.state == "confirmed"
    assert {:ok, _} = Volunteers.confirm(scope, batch.id)
    assert Repo.aggregate(Signup, :count) == 1
    assert Repo.aggregate(Invitation, :count) == 1
    assert :ok = Volunteers.dispatch_batch(scope, batch.id)
    assert_receive {:email, %{to: [{"", "camille@example.org"}]} = email}
    assert email.to == [{"", "camille@example.org"}]
    assert email.cc == [] and email.bcc == []
    assert email.html_body =~ "volunteer signup sheet"
    refute email.html_body =~ "private note"
    [_, token] = Regex.run(~r{/users/log-in/([^"\s<]+)}, email.html_body)

    assert {:ok, {%User{confirmed_at: confirmed_at}, _}} =
             Accounts.login_user_by_magic_link(token)

    assert confirmed_at
    assert :ok = Volunteers.dispatch_batch(scope, batch.id)
    refute_receive {:email, %{to: [{"", "camille@example.org"}]}}
    assert [%{status: "accepted"}] = Repo.all(Invitation)
    assert Enum.any?(Volunteers.events(scope, batch.id), &(&1.action == "invitation_accepted"))
  end

  test "row overrides survive changing defaults and resuming the wizard", %{
    scope: scope,
    montreal: montreal,
    quebec: quebec
  } do
    first = Input.normalize(%{"email" => "one@example.org", "selected" => true})

    second =
      Input.normalize(%{
        "email" => "two@example.org",
        "selected" => true,
        "group_id" => quebec.id,
        "discord_handle" => "example"
      })

    attrs = %{
      "rows" => [first, second],
      "default_group_id" => montreal.id,
      "step" => "contact",
      "wizard_row" => second["key"]
    }

    {:ok, batch} = Volunteers.save_draft(scope, nil, attrs)

    {:ok, batch} =
      Volunteers.save_draft(scope, batch, Map.put(attrs, "default_group_id", quebec.id))

    {:ok, resumed} = Volunteers.get_batch(scope, batch.id)
    assert resumed.wizard_row == second["key"]
    assert resumed.rows |> List.last() |> Map.get("discord_handle") == "example"

    assert [%{group: ^quebec}, %{group: ^quebec}] =
             Volunteers.review(scope, resumed.rows, resumed.default_group_id)

    {:ok, batch} = Volunteers.save_draft(scope, resumed, attrs)
    assert {:ok, _} = Volunteers.confirm(scope, batch.id)

    assert Enum.map(Volunteers.results(scope, batch.id), & &1.group_id) == [
             montreal.id,
             quebec.id
           ]
  end

  test "revoked managers cannot confirm or read a saved batch", %{
    scope: admin,
    montreal: group,
    quebec: other
  } do
    manager = user_fixture() |> change(confirmed_at: DateTime.utc_now(:second)) |> Repo.update!()
    {:ok, assignment} = Volunteers.assign_manager(admin, group.id, manager.email)
    scope = Scope.for_user(manager)
    row = Input.normalize(%{"email" => "scope@example.org", "selected" => true})

    {:ok, batch} =
      Volunteers.save_draft(scope, nil, %{"rows" => [row], "default_group_id" => group.id})

    assert {:error, :unauthorized} =
             Volunteers.save_draft(scope, batch, %{
               "rows" => [Map.put(row, "group_id", other.id)],
               "default_group_id" => group.id
             })

    :ok = Volunteers.revoke_manager(admin, assignment.id)
    assert {:error, :unauthorized} = Volunteers.confirm(scope, batch.id)
    assert {:error, :unauthorized} = Volunteers.get_batch(scope, batch.id)
    assert Volunteers.results(scope, batch.id) == []
    assert Repo.aggregate(Signup, :count) == 0
    assert Repo.aggregate(Invitation, :count) == 0
  end

  test "retry keeps accounts and accepted emails; ambiguous delivery requires reconciliation", %{
    scope: scope,
    montreal: group
  } do
    rows =
      for n <- 1..3,
          do: Input.normalize(%{"email" => "retry#{n}@example.org", "selected" => true})

    {:ok, batch} =
      Volunteers.save_draft(scope, nil, %{"rows" => rows, "default_group_id" => group.id})

    {:ok, _} = Volunteers.confirm(scope, batch.id)

    :ok =
      Volunteers.dispatch_batch(scope, batch.id, fn user ->
        case user.email do
          "retry1@example.org" -> {:ok, %{id: "accepted-1"}}
          "retry2@example.org" -> {:error, :rejected}
          _ -> {:error, :timeout}
        end
      end)

    failed = Repo.get_by!(Invitation, status: "failed")
    unknown = Repo.get_by!(Invitation, status: "unknown")
    accepted = Repo.get_by!(Invitation, status: "accepted")
    assert {:error, :not_retryable} = Volunteers.retry(scope, unknown.id)
    assert {:error, :not_retryable} = Volunteers.retry(scope, accepted.id)
    assert {:ok, _} = Volunteers.retry(scope, failed.id)

    :ok =
      Volunteers.dispatch_batch(scope, batch.id, fn user ->
        assert user.email == "retry2@example.org"
        {:ok, %{id: "accepted-2"}}
      end)

    assert Repo.aggregate(Signup, :count) == 3

    assert {:ok, _} =
             Volunteers.reconcile(scope, unknown.id, "failed", "provider lookup reference")

    assert {:ok, _} = Volunteers.retry(scope, unknown.id)
  end

  test "existing profile and suppression survive imports", %{scope: scope, montreal: group} do
    user =
      user_fixture(%{email: "existing-volunteer@example.org"})
      |> change(name: "Verified name")
      |> Repo.update!()

    Repo.insert!(%Profile{user_id: user.id, details: %{"bio" => "Existing bio"}})

    rows = [
      Input.normalize(%{
        "email" => user.email,
        "name" => "Sheet name",
        "bio" => "Sheet bio",
        "selected" => true
      })
    ]

    {:ok, batch} =
      Volunteers.save_draft(scope, nil, %{"rows" => rows, "default_group_id" => group.id})

    assert {:ok, _} = Volunteers.confirm(scope, batch.id)
    assert Accounts.get_user!(user.id).name == "Verified name"
    assert Repo.get_by!(Profile, user_id: user.id).details["bio"] == "Existing bio"
    assert [%{errors: %{"email" => :already_imported}}] = Volunteers.review(scope, rows, group.id)

    {:ok, _} =
      PauseAiCa.ContactMigration.import_selected(
        [%{"email" => "blocked@example.org", "status" => "do_not_contact"}],
        "test.csv",
        "test",
        scope.user
      )

    assert [%{errors: %{"email" => :suppressed}}] =
             Volunteers.review(
               scope,
               [Input.normalize(%{"email" => "blocked@example.org"})],
               group.id
             )
  end

  test "profile drafts are local, resumable and separate from publication", %{scope: scope} do
    attrs = %{
      "bio" => "Interested in organizing",
      "availability_hours_per_week" => "4",
      "skills" => "Organizing / Facilitation: advanced"
    }

    assert {:ok, profile} = Volunteers.save_profile(scope, attrs, "contribution")
    assert profile.details == %{}
    assert Volunteers.get_profile(scope).draft["bio"] == attrs["bio"]

    assert {:error, %{"availability_hours_per_week" => :invalid_hours}} =
             Volunteers.save_profile(
               scope,
               Map.put(attrs, "availability_hours_per_week", "4.5"),
               "review"
             )

    assert {:ok, profile} = Volunteers.save_profile(scope, attrs, "review", true)

    assert profile.details["skills"] == [
             %{"category" => "Organizing", "name" => "Facilitation", "proficiency" => "advanced"}
           ]

    assert profile.details["availability_hours_per_week"] == 4
  end

  test "stale drafts do not overwrite later saved work", %{scope: scope, montreal: group} do
    attrs = %{"rows" => [], "default_group_id" => group.id}
    {:ok, original} = Volunteers.save_draft(scope, nil, attrs)

    assert {:ok, changed} =
             Volunteers.save_draft(scope, original, Map.put(attrs, "source", "New source"))

    assert {:error, _} =
             Volunteers.save_draft(scope, original, Map.put(attrs, "source", "Stale source"))

    assert Repo.get!(Batch, changed.id).source == "New source"
  end

  test "queue recovery never repeats an interrupted send and rechecks suppression", %{
    scope: scope,
    montreal: group
  } do
    rows =
      for n <- 1..2,
          do: Input.normalize(%{"email" => "queue#{n}@example.org", "selected" => true})

    {:ok, batch} =
      Volunteers.save_draft(scope, nil, %{"rows" => rows, "default_group_id" => group.id})

    {:ok, _} = Volunteers.confirm(scope, batch.id)
    [first, second] = Volunteers.results(scope, batch.id)
    attempt = hd(first.invitations)

    attempt
    |> change(status: "sending", attempted_at: DateTime.add(DateTime.utc_now(:second), -1000))
    |> Repo.update!()

    {:ok, _} =
      PauseAiCa.ContactMigration.import_selected(
        [%{"email" => second.email, "status" => "do_not_contact"}],
        "synthetic.csv",
        "test",
        scope.user
      )

    Volunteers.dispatch_pending()
    assert Repo.get!(Invitation, attempt.id).status == "unknown"
    assert Repo.get!(Invitation, hd(second.invitations).id).status == "suppressed"
    refute_receive {:email, %{to: [{"", "queue1@example.org"}]}}
    refute_receive {:email, %{to: [{"", "queue2@example.org"}]}}
    assert Enum.any?(Volunteers.events(scope, batch.id), &(&1.action == "invitation_unknown"))
  end

  test "CSV preserves accented French headers and multiline comments" do
    csv =
      "\uFEFFNom,Courriel,Code postal,Groupe,Commentaires\r\nCamille,camille@example.org,H2X 1Y4,Montréal,\"First line, then\nsecond line\"\r\n"

    assert {:ok, decoded} = Input.csv(csv)
    assert {:ok, [row]} = Input.mapped(decoded, decoded.mapping)
    assert row["name"] == "Camille"
    assert row["notes"] == "First line, then\nsecond line"
    assert row["postal_code"] == "H2X1Y4"
    assert {:error, :invalid_csv} = Input.csv("email\na@example.org,extra\n")
    assert {:error, :invalid_mapping} = Input.mapped(decoded, List.duplicate("email", 5))
  end
end
