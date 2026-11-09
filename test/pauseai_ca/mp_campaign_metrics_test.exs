defmodule PauseAiCa.MPCampaignMetricsTest do
  use PauseAiCa.DataCase, async: true
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Engagement, MPTemplates, Repo}
  alias PauseAiCa.Campaigns.SendIntent

  test "campaign totals distinguish accepted sends, pending handoffs and explicit confirmations" do
    user = user_fixture()
    scope = Accounts.Scope.for_user(user)
    campaign_id = Ecto.UUID.generate()

    {:ok, action} =
      Engagement.create_action(scope, %{
        "action_type" => "contacted_representative",
        "happened_on" => Date.utc_today()
      })

    insert_intent(campaign_id, user.id, "handoff", action.id)
    assert MPTemplates.completed_count(campaign_id) == 0
    assert {:ok, _} = Engagement.confirm_action(scope, action)
    assert MPTemplates.completed_count(campaign_id) == 1
    assert {:ok, _} = Engagement.confirm_action(scope, action)
    assert MPTemplates.completed_count(campaign_id) == 1
    insert_intent(campaign_id, user.id, "accepted", nil)
    insert_intent(campaign_id, user.id, "unknown", nil)
    insert_intent(Ecto.UUID.generate(), user.id, "accepted", nil)
    assert MPTemplates.completed_count(campaign_id) == 2
  end

  defp insert_intent(campaign_id, actor_id, state, action_id) do
    Repo.insert!(%SendIntent{
      fingerprint: :crypto.strong_rand_bytes(32),
      actor_id: actor_id,
      kind: if(state == "handoff", do: "handoff", else: "assisted"),
      state: state,
      template_id: campaign_id,
      template_revision: 1,
      action_id: action_id,
      accepted_at: if(state == "accepted", do: DateTime.utc_now())
    })
  end
end
