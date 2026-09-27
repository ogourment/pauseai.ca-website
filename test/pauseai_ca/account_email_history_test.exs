defmodule PauseAiCa.AccountEmailHistoryTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{AccountEmailHistory, AccountManagement, Volunteers}
  alias PauseAiCa.Accounts.Scope

  setup do
    Application.put_env(:pauseai_ca, :brevo_history_req_options,
      plug: &PauseAiCa.BrevoHistoryStub.call/2
    )

    Application.put_env(:pauseai_ca, :history_test_process, self())

    on_exit(fn ->
      Application.delete_env(:pauseai_ca, :brevo_history_req_options)
      Application.delete_env(:pauseai_ca, :history_test_process)
      Application.delete_env(:pauseai_ca, :history_test_failure)
    end)

    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    %{scope: Scope.for_user(admin), target: user_fixture()}
  end

  test "merges provider metadata and excludes another sender and authentication data", c do
    assert {:ok, history} =
             AccountEmailHistory.load(c.scope, c.target.id, AccountEmailHistory.defaults())

    assert {:ok, %{rows: [mail], partial: true}} = history.transactional
    assert mail.subject == "Your sign-in link"
    assert Enum.map(mail.events, & &1.status) == ["requests", "delivered", "clicks"]
    assert {:ok, %{rows: [campaign]}} = history.campaigns
    assert campaign.subject == "September update"
    refute inspect(history) =~ "secret.example"
    refute inspect(history) =~ "192.0.2.1"
    refute inspect(history) =~ "Other organization"
    assert_received {:history_request, "GET", "/v3/smtp/statistics/events"}
    Application.put_env(:pauseai_ca, :history_test_failure, true)

    assert {:ok, %{campaigns: {:error, :rate_limited}, transactional: {:ok, _}}} =
             AccountEmailHistory.load(c.scope, c.target.id, AccountEmailHistory.defaults())
  end

  test "scope is checked before provider I/O and reassignment revokes access", c do
    {:ok, group} = Volunteers.create_group(c.scope, %{"name" => "Montréal"})
    manager = user_fixture()
    {:ok, _} = Volunteers.assign_manager(c.scope, group.id, manager.email)
    scope = Scope.for_user(manager)

    assert {:error, :unauthorized} =
             AccountEmailHistory.load(scope, c.target.id, AccountEmailHistory.defaults())

    refute_received {:history_request, _, _}
    assert {:ok, _} = AccountManagement.update(c.scope, c.target.id, %{"group_id" => group.id})
    assert {:ok, _} = AccountEmailHistory.load(scope, c.target.id, AccountEmailHistory.defaults())
    assert {:ok, _} = AccountManagement.update(c.scope, c.target.id, %{"group_id" => ""})

    assert {:error, :unauthorized} =
             AccountEmailHistory.load(scope, c.target.id, AccountEmailHistory.defaults())
  end

  test "invalid date and page bounds are rejected without provider calls", c do
    for filters <- [
          %{"from" => "bad"},
          %{"from" => "2020-01-01", "to" => "2021-01-01", "page" => "1"},
          Map.put(AccountEmailHistory.defaults(), "page", "0")
        ] do
      assert {:error, :invalid_range} = AccountEmailHistory.load(c.scope, c.target.id, filters)
    end

    refute_received {:history_request, _, _}
  end
end
