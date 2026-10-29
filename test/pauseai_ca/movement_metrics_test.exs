defmodule PauseAiCa.MovementMetricsTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{MovementMetrics, Repo}
  alias PauseAiCa.Newsletters.{Batch, Delivery, Drafts, ResultSnapshot}

  test "mail reports exclude staging and unattempted campaigns and retain coverage and overlap" do
    user = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = PauseAiCa.Accounts.Scope.for_user(user)
    at = ~U[2026-10-20 12:00:00.000000Z]

    campaign(scope, "production", true, %{opened: 2, proxy_opened: 1}, at, true)
    campaign(scope, "production", true, %{opened: 1, proxy_opened: 1}, at, false)
    campaign(scope, "production", true, nil, at, false)
    campaign(scope, "staging", true, %{opened: 99}, at, false)
    campaign(scope, "production", false, %{opened: 99}, at, false)

    campaign(scope, "production", true, %{opened: 99}, at, false, "contacts")
    campaign(scope, "production", true, %{opened: 0}, at, false, "list")

    assert MovementMetrics.summary().newsletter == %{
             reported_opens: 3,
             proxy_opens: 2,
             campaigns: 4,
             reports: 3,
             partial_reports: 1,
             oldest_refresh: at
           }
  end

  test "memberships remain separate from people and tasks include groups without an incubator" do
    user = user_fixture()
    now = DateTime.utc_now()

    groups =
      for published <- [true, false] do
        group = Repo.insert!(%PauseAiCa.Volunteers.Group{name: "Synthetic group #{published}"})

        Repo.insert!(%PauseAiCa.Incubators.Profile{
          group_id: group.id,
          name_en: "Local group",
          name_fr: "Groupe local",
          published: published
        })

        Repo.insert!(%PauseAiCa.Incubators.Membership{
          group_id: group.id,
          user_id: user.id,
          display_name: "Synthetic member",
          status: if(published, do: "approved", else: "admitted"),
          conduct_at: now
        })

        group
      end

    Repo.insert!(%PauseAiCa.Incubators.Membership{
      group_id: hd(groups).id,
      user_id: user_fixture().id,
      display_name: "Pending member",
      conduct_at: now
    })

    other_group = Repo.insert!(%PauseAiCa.Volunteers.Group{name: "Organizer group"})

    for status <- ~w(open in_progress in_review done cancelled) do
      Repo.insert!(%PauseAiCa.Tasks.Task{
        group_id: other_group.id,
        requester_id: user.id,
        title: "Synthetic task",
        status: status
      })
    end

    metrics = MovementMetrics.summary()
    assert metrics.incubators == %{published: 1, approved_memberships: 2, pending_requests: 1}
    assert metrics.tasks == %{active: 3, completed: 1}
    assert metrics.newsletter.reported_opens == 0
    assert metrics.newsletter.oldest_refresh == nil
  end

  defp campaign(scope, environment, attempted?, observations, at, partial?, mode \\ "newsletter") do
    {:ok, draft} = Drafts.create(scope)

    batch =
      Repo.insert!(%Batch{
        draft_id: draft.id,
        owner_id: scope.user.id,
        draft_revision: 1,
        recipient_mode: mode,
        recipient_keys: [],
        sender_name: "Synthetic sender",
        sender_email: "sender@example.org",
        delivery_environment: environment,
        subject: "Synthetic newsletter",
        source: "Synthetic body",
        preparation_key: :crypto.strong_rand_bytes(32),
        audience_digest: :crypto.strong_rand_bytes(32),
        reviewed_at: at
      })

    Repo.insert!(%Delivery{
      batch_id: batch.id,
      recipient_key: "synthetic",
      email: "same-address@example.org",
      withdrawal_token: "synthetic",
      authorizing_admin_id: if(attempted?, do: scope.user.id),
      attempted_at: if(attempted?, do: at)
    })

    if observations do
      Repo.insert!(%ResultSnapshot{
        batch_id: batch.id,
        observed: observations,
        partial: partial?,
        refreshed_at: at
      })
    end
  end
end
