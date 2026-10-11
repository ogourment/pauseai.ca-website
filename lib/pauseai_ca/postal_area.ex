defmodule PauseAiCa.PostalArea do
  @moduledoc "Canadian postal-area normalization shared by account and newsletter forms."
  @pattern ~r/^[ABCEGHJKLMNPRSTVXY]\d[ABCEGHJKLMNPRSTVWXYZ]$/
  def pattern, do: @pattern
  def valid?(value), do: is_binary(value) and Regex.match?(@pattern, value)

  def normalize(value) when is_binary(value),
    do: value |> String.upcase() |> String.replace(~r/\s+/, "")
end
