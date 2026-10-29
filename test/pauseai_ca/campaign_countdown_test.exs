defmodule PauseAiCa.CampaignCountdownTest do
  use ExUnit.Case, async: true
  alias PauseAiCa.Donations.{Campaign, PagePayload}

  @closing ~U[2026-11-28 06:59:59Z]
  test "shared deadline respects the configured offset and exact closing boundary" do
    page = %{
      "campaign" => %{
        "enabled" => true,
        "closes_at" => "2026-11-27T23:59:59-07:00",
        "urgent_window_days" => 7
      }
    }

    state = Campaign.countdown(page, DateTime.add(@closing, -8 * 86_400))
    assert state.closes_at == @closing
    assert state.closing_date == "2026-11-27"
    assert state.parts.days == 8
    refute state.urgent?
    assert Campaign.countdown(page, DateTime.add(@closing, -7 * 86_400)).urgent?
    assert Campaign.countdown(page, DateTime.add(@closing, -1)).parts.seconds == 1
    assert Campaign.countdown(page, @closing) == nil
    assert Campaign.countdown(page, DateTime.add(@closing, 1)) == nil

    assert Campaign.countdown(
             put_in(page, ["campaign", "enabled"], false),
             DateTime.add(@closing, -1)
           ) == nil
  end

  test "old CMS snapshots inherit configuration without writes; malformed deadlines never show urgency" do
    assert Campaign.countdown(%{}, ~U[2026-10-29 12:00:00Z])

    assert Campaign.countdown(
             %{"campaign" => %{"closes_at" => "2026-11-27"}},
             ~U[2026-10-29 12:00:00Z]
           ) == nil

    old = PagePayload.defaults() |> Map.delete("campaign")
    assert {:ok, ^old} = PagePayload.validate(old, :publish)

    for value <- ["2026-11-27", "bad", "2026-11-27T23:59:59"] do
      assert {:error, _} =
               old
               |> Map.put("campaign", %{
                 "enabled" => true,
                 "closes_at" => value,
                 "urgent_window_days" => 7
               })
               |> PagePayload.validate(:publish)
    end
  end
end
