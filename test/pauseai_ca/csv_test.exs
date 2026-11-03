defmodule PauseAiCa.CSVTest do
  use ExUnit.Case, async: true
  alias PauseAiCa.CSV

  test "quotes commas, embedded quotes and newlines without losing Unicode" do
    assert CSV.encode([["email"], ["Élodie, \"press\"\r\n@example.org"]]) ==
             "\"email\"\r\n\"Élodie, \"\"press\"\"\r\n@example.org\"\r\n"
  end

  test "neutralizes spreadsheet formula prefixes, including leading whitespace and controls" do
    for value <- ["=1+1", "+press@example.org", "-1", "@SUM(1)", "\t=1", "\r\n+1", "\uFEFF=1"] do
      assert CSV.encode([[value]]) == "\"'#{value}\"\r\n"
    end

    assert CSV.encode([["press+news@example.org"]]) == "\"press+news@example.org\"\r\n"
  end
end
