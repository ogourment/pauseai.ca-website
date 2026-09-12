defmodule PauseAiCa.Engagement.SignupFunnelTest do
  use PauseAiCa.DataCase, async: true
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Engagement, EngagementFixtures}
  alias PauseAiCa.Accounts.Scope

  test "creation cohort owns late confirmations and counts people once per stage" do
    yesterday = Date.add(Date.utc_today(), -1)
    user = user_fixture()

    Repo.update!(
      Ecto.Changeset.change(user,
        inserted_at: DateTime.new!(yesterday, ~T[12:00:00]),
        signup_entry_point: "header"
      )
    )

    EngagementFixtures.action_fixture(Scope.for_user(user), %{
      confirmed_at: DateTime.utc_now(:second)
    })

    EngagementFixtures.action_fixture(Scope.for_user(user), %{
      confirmed_at: DateTime.utc_now(:second)
    })

    assert %{created: 0, confirmed: 0, first_action: 0} =
             Engagement.signup_funnel(%{"from" => Date.to_iso8601(Date.utc_today())})

    assert %{created: 1, confirmed: 1, first_action: 1, trends: %{first_action: [1]}} =
             Engagement.signup_funnel(%{
               "from" => Date.to_iso8601(yesterday),
               "to" => Date.to_iso8601(yesterday)
             })
  end

  test "legacy attribution remains unknown and promoted superadmins are excluded" do
    user_fixture()
    admin = user_fixture()
    Repo.update!(Ecto.Changeset.change(admin, superadmin: true, signup_entry_point: "header"))
    assert %{created: 1, confirmed: 1, sources: sources} = Engagement.signup_funnel()
    assert {"unknown", 1} in sources
    assert %{created: 0} = Engagement.signup_funnel(%{"source" => "header"})
    assert %{created: 1} = Engagement.signup_funnel(%{"source" => "unknown"})
  end

  test "pending accounts do not become confirmed through unconfirmed actions" do
    {:ok, pending} = PauseAiCa.Accounts.register_user(%{email: unique_user_email()})
    EngagementFixtures.action_fixture(Scope.for_user(pending), %{confirmed_at: nil})
    assert %{created: 1, confirmed: 0, pending: 1, first_action: 0} = Engagement.signup_funnel()
  end

  test "invalid filters fall back safely and excessive ranges are bounded" do
    assert %{source: "all", to: today} =
             Engagement.signup_funnel(%{"source" => "forged", "to" => "invalid"})

    assert today == Date.utc_today()
    assert %{from: from, to: to} = Engagement.signup_funnel(%{"from" => "1900-01-01"})
    assert Date.diff(to, from) == 365
  end
end
