defmodule PauseAiCa.LocalGroups do
  @moduledoc "Explicitly published local directory, separate from private volunteer groups."
  def for_fsa(fsa) when is_binary(fsa) do
    Application.get_env(:pauseai_ca, :public_local_groups, [])
    |> Enum.filter(fn group ->
      fsa in group.fsas and
        match?(%URI{scheme: "https", host: host} when is_binary(host), URI.parse(group.join_url))
    end)
  end

  def for_fsa(_), do: []
end
