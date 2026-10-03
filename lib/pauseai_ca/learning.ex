defmodule PauseAiCa.Learning do
  @moduledoc "Shared, locale-specific knowledge nuggets and stable learning IDs."
  @external_resource "priv/learning/nuggets.json"
  @nuggets "priv/learning/nuggets.json" |> File.read!() |> Jason.decode!()
  def nuggets(locale) do
    @nuggets
    |> Enum.map(&Map.merge(&1, &1[locale]))
    |> Enum.sort_by(&(&1["language"] != locale))
  end

  def ids, do: Enum.map(@nuggets, & &1["id"])
  def valid_ids(ids) when is_list(ids), do: ids |> Enum.filter(&(&1 in ids())) |> Enum.uniq()
  def valid_ids(_), do: []
end
