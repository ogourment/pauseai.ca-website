defmodule PauseAiCa.EngagementFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `PauseAiCa.Engagement` context.
  """

  @doc """
  Generate a action.
  """
  def action_fixture(scope, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        action_type: "learned",
        happened_on: ~D[2026-07-27],
        notes: "some notes"
      })

    {:ok, action} = PauseAiCa.Engagement.create_action(scope, attrs)
    action
  end
end
