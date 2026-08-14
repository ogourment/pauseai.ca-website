defmodule PauseAiCa.EngagementTest do
  use PauseAiCa.DataCase

  alias PauseAiCa.Engagement

  describe "actions" do
    alias PauseAiCa.Engagement.Action

    import PauseAiCa.AccountsFixtures, only: [user_scope_fixture: 0]
    import PauseAiCa.EngagementFixtures

    @invalid_attrs %{action_type: nil, happened_on: nil, notes: nil}

    test "list_actions/1 returns all scoped actions" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      action = action_fixture(scope)
      other_action = action_fixture(other_scope)
      assert Engagement.list_actions(scope) == [action]
      assert Engagement.list_actions(other_scope) == [other_action]
    end

    test "get_action!/2 returns the action with given id" do
      scope = user_scope_fixture()
      action = action_fixture(scope)
      other_scope = user_scope_fixture()
      assert Engagement.get_action!(scope, action.id) == action
      assert_raise Ecto.NoResultsError, fn -> Engagement.get_action!(other_scope, action.id) end
    end

    test "create_action/2 with valid data creates a action" do
      valid_attrs = %{
        action_type: "conversation",
        happened_on: ~D[2026-07-27],
        notes: "some notes"
      }

      scope = user_scope_fixture()

      assert {:ok, %Action{} = action} = Engagement.create_action(scope, valid_attrs)
      assert action.action_type == "conversation"
      assert action.happened_on == ~D[2026-07-27]
      assert action.notes == "some notes"
      assert action.user_id == scope.user.id
    end

    test "create_action/2 allows an action without a private note" do
      scope = user_scope_fixture()

      assert {:ok, %Action{notes: nil}} =
               Engagement.create_action(scope, %{
                 action_type: "learned",
                 happened_on: ~D[2026-07-28]
               })
    end

    test "create_action/2 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      assert {:error, %Ecto.Changeset{}} = Engagement.create_action(scope, @invalid_attrs)
    end

    test "update_action/3 with valid data updates the action" do
      scope = user_scope_fixture()
      action = action_fixture(scope)

      update_attrs = %{
        action_type: "organized",
        happened_on: ~D[2026-07-28],
        notes: "some updated notes"
      }

      assert {:ok, %Action{} = action} = Engagement.update_action(scope, action, update_attrs)
      assert action.action_type == "organized"
      assert action.happened_on == ~D[2026-07-28]
      assert action.notes == "some updated notes"
    end

    test "update_action/3 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      action = action_fixture(scope)

      assert_raise MatchError, fn ->
        Engagement.update_action(other_scope, action, %{})
      end
    end

    test "update_action/3 with invalid data returns error changeset" do
      scope = user_scope_fixture()
      action = action_fixture(scope)
      assert {:error, %Ecto.Changeset{}} = Engagement.update_action(scope, action, @invalid_attrs)
      assert action == Engagement.get_action!(scope, action.id)
    end

    test "delete_action/2 deletes the action" do
      scope = user_scope_fixture()
      action = action_fixture(scope)
      assert {:ok, %Action{}} = Engagement.delete_action(scope, action)
      assert_raise Ecto.NoResultsError, fn -> Engagement.get_action!(scope, action.id) end
    end

    test "delete_action/2 with invalid scope raises" do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      action = action_fixture(scope)
      assert_raise MatchError, fn -> Engagement.delete_action(other_scope, action) end
    end

    test "change_action/2 returns a action changeset" do
      scope = user_scope_fixture()
      action = action_fixture(scope)
      assert %Ecto.Changeset{} = Engagement.change_action(scope, action)
    end
  end

  describe "movement metrics" do
    import PauseAiCa.AccountsFixtures, only: [user_scope_fixture: 0]
    import PauseAiCa.EngagementFixtures

    test "returns daily trends and aggregate visit totals" do
      today = ~D[2026-08-06]
      scope = user_scope_fixture()

      action_fixture(scope, %{
        confirmed_at: DateTime.new!(today, ~T[12:00:00])
      })

      Engagement.record_visit(Date.add(today, -1))
      Engagement.record_visit(today)
      Engagement.record_visit(today)

      metrics = Engagement.metrics(today)

      assert metrics.visits == 3
      assert Enum.take(metrics.trends.visits, -2) == [1, 2]
      assert List.last(metrics.trends.actions) == 1
      assert List.last(metrics.trends.active_people) == 1
      assert length(metrics.trends.users) == 14
    end
  end

  describe "learning metrics" do
    test "counts distinct anonymous and account-linked people across signals" do
      user = PauseAiCa.AccountsFixtures.user_fixture()
      first_browser = Ecto.UUID.generate()
      second_browser = Ecto.UUID.generate()

      assert {:ok, _} =
               Engagement.record_learning_signal(
                 first_browser,
                 nil,
                 "question_answered",
                 "risk",
                 "4"
               )

      assert {:ok, _} =
               Engagement.record_learning_signal(first_browser, nil, "learn_page_visited")

      assert {:ok, _} =
               Engagement.record_learning_signal(
                 second_browser,
                 user,
                 "resource_opened",
                 "pauseai-learn"
               )

      assert %{people: 2, breakdown: breakdown} = Engagement.learning_metrics()
      assert breakdown.question_answers == 1
      assert breakdown.learn_page_visitors == 1
      assert breakdown.resources_opened == 1
    end
  end
end
