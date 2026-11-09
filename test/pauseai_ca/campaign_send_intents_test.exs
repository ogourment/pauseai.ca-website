defmodule PauseAiCa.Campaigns.SendIntentsTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Engagement
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Campaigns.{Letter, RateLimit, SendIntent, SendIntents}

  setup do
    RateLimit.reset()
    user = user_fixture()
    scope = Scope.for_user(user)

    letter = %Letter{
      to: "mp@example.org",
      subject: "A personal reviewed request",
      body: "Please support effective oversight. Thank you, Camille."
    }

    %{scope: scope, letter: letter, supporter: %{name: "Camille", email: user.email}}
  end

  test "one reviewed letter has one accepted delivery and account action across repeated submissions",
       c do
    {:ok, calls} = Agent.start_link(fn -> [] end)

    adapter = fn _letter, _supporter, opts ->
      Agent.update(calls, &[opts[:intent_id] | &1])
      {:ok, %{id: "synthetic-provider-id"}}
    end

    template = %{id: Ecto.UUID.generate(), revision: 3}

    assert {:ok, first} =
             SendIntents.deliver(c.scope, c.letter, c.supporter,
               adapter: adapter,
               template: template
             )

    assert {:ok, again} =
             SendIntents.deliver(c.scope, c.letter, c.supporter,
               adapter: adapter,
               template: template
             )

    assert first.id == again.id
    assert Agent.get(calls, & &1) == [first.id]
    assert [%{id: action_id, confirmed_at: %DateTime{}}] = Engagement.list_actions(c.scope)
    assert first.action_id == action_id
    assert Repo.get!(SendIntent, first.id).state == "accepted"
    assert Repo.aggregate(SendIntent, :count) == 1
    assert first.template_id == template.id
    refute Map.has_key?(Map.from_struct(first), :body)
    refute Map.has_key?(Map.from_struct(first), :sender_email)
  end

  test "simultaneous duplicate submission sees a durable hold while the single adapter is in flight",
       c do
    parent = self()

    adapter = fn _, _, _ ->
      send(parent, {:in_flight, self()})

      receive do
        :finish -> {:ok, %{id: "synthetic"}}
      end
    end

    first =
      Task.async(fn -> SendIntents.deliver(c.scope, c.letter, c.supporter, adapter: adapter) end)

    assert_receive {:in_flight, worker}

    assert {:error, :delivery_unknown} =
             SendIntents.deliver(c.scope, c.letter, c.supporter,
               adapter: fn _, _, _ -> flunk("duplicate delivery") end
             )

    assert [] == Engagement.list_actions(c.scope)
    send(worker, :finish)
    assert {:ok, accepted} = Task.await(first)
    assert [action] = Engagement.list_actions(c.scope)
    assert accepted.action_id == action.id
  end

  test "explicit rejection can retry the same intent; uncertain acceptance cannot retry", c do
    assert {:error, :delivery_failed} =
             SendIntents.deliver(c.scope, c.letter, c.supporter,
               adapter: fn _, _, _ -> {:error, :rejected} end
             )

    [rejected] = Repo.all(SendIntent)
    assert rejected.state == "rejected"
    assert [] == Engagement.list_actions(c.scope)

    assert {:ok, accepted} =
             SendIntents.deliver(c.scope, c.letter, c.supporter,
               adapter: fn _, _, _ -> {:ok, %{}} end
             )

    assert accepted.id == rejected.id
    changed = %{c.letter | subject: "Another reviewed request"}

    assert {:error, :delivery_unknown} =
             SendIntents.deliver(c.scope, changed, c.supporter,
               adapter: fn _, _, _ -> {:error, :timeout} end
             )

    assert {:error, :delivery_unknown} =
             SendIntents.deliver(c.scope, changed, c.supporter,
               adapter: fn _, _, _ -> flunk("unknown must not retry") end
             )

    assert length(Engagement.list_actions(c.scope)) == 1
  end

  test "provider acceptance followed by database failure remains held and creates no false completed action",
       c do
    adapter = fn _, _, _ ->
      Repo.query!("""
      CREATE FUNCTION pg_temp.reject_campaign_acceptance() RETURNS trigger AS $$
      BEGIN
        IF NEW.state = 'accepted' THEN
          RAISE EXCEPTION 'synthetic acceptance commit failure';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql
      """)

      Repo.query!(
        "CREATE TRIGGER reject_campaign_acceptance BEFORE UPDATE ON campaign_send_intents FOR EACH ROW EXECUTE FUNCTION pg_temp.reject_campaign_acceptance()"
      )

      {:ok, %{id: "synthetic-accepted-provider-id"}}
    end

    assert {:error, :delivery_unknown} =
             SendIntents.deliver(c.scope, c.letter, c.supporter, adapter: adapter)

    assert [%{state: "submitting"}] = Repo.all(SendIntent)
    assert [] == Engagement.list_actions(c.scope)

    assert {:error, :delivery_unknown} =
             SendIntents.deliver(c.scope, c.letter, c.supporter,
               adapter: fn _, _, _ -> flunk("must reconcile") end
             )
  end

  test "a friend's own action belongs only to that confirmed account and stale sender ownership is rejected",
       c do
    friend = user_fixture()
    friend_scope = Scope.for_user(friend)
    adapter = fn _, _, _ -> {:ok, %{}} end
    assert {:ok, own} = SendIntents.deliver(c.scope, c.letter, c.supporter, adapter: adapter)

    assert {:ok, theirs} =
             SendIntents.deliver(friend_scope, c.letter, %{name: "Friend", email: friend.email},
               adapter: adapter
             )

    assert own.action_id != theirs.action_id
    assert [mine] = Engagement.list_actions(c.scope)
    assert mine.id == own.action_id
    assert [friend_action] = Engagement.list_actions(friend_scope)
    assert friend_action.id == theirs.action_id
    assert_raise Ecto.NoResultsError, fn -> Engagement.get_action!(c.scope, friend_action.id) end
    Repo.update!(Ecto.Changeset.change(c.scope.user, confirmed_at: nil))

    assert {:error, :sender_unverified} =
             SendIntents.deliver(c.scope, %{c.letter | subject: "changed"}, c.supporter,
               adapter: fn _, _, _ -> flunk("stale account") end
             )
  end

  test "external handoff is one pending actor action, and confirmation is idempotent", c do
    assert {:ok, first} = SendIntents.handoff(c.scope, c.letter, c.supporter)
    assert {:ok, repeated} = SendIntents.handoff(c.scope, c.letter, c.supporter)
    assert first.action_id == repeated.action_id
    assert [action] = Engagement.list_pending_actions(c.scope)
    assert {:ok, confirmed} = Engagement.confirm_action(c.scope, action)
    assert {:ok, same} = Engagement.confirm_action(c.scope, action)
    assert confirmed.confirmed_at == same.confirmed_at
    assert [] == Engagement.list_pending_actions(c.scope)
    assert [^same] = Engagement.list_actions(c.scope)
  end
end
