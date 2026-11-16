defmodule PauseAiCaWeb.AssistantReviewParameterPrivacyTest do
  use ExUnit.Case, async: true

  test "review confirmation tokens and operator reasons are filtered from parameter logs" do
    assert Phoenix.Logger.filter_values(%{
             "review" => %{"token" => "synthetic-token", "reason" => "private operator note"}
           }) == %{"review" => "[FILTERED]"}
  end
end
