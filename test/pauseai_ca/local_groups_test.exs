defmodule PauseAiCa.LocalGroupsTest do
  use ExUnit.Case, async: false

  test "LEARN-REQ-08 only explicitly published groups in the postal area match" do
    previous = Application.get_env(:pauseai_ca, :public_local_groups)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pauseai_ca, :public_local_groups, previous),
        else: Application.delete_env(:pauseai_ca, :public_local_groups)
    end)

    published = %{
      name: "Synthetic example group",
      description: "Review fixture",
      fsas: ["H2X"],
      join_url: "https://example.org/join"
    }

    Application.put_env(:pauseai_ca, :public_local_groups, [
      published,
      %{published | join_url: "javascript:alert(1)"}
    ])

    assert PauseAiCa.LocalGroups.for_fsa("H2X") == [published]
    assert PauseAiCa.LocalGroups.for_fsa("M5V") == []
    assert PauseAiCa.LocalGroups.for_fsa(nil) == []
  end
end
