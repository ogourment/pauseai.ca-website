defmodule PauseAiCa.Mail.Render do
  @moduledoc "Draft rendering only. No delivery API. Same sanitized rendering powers every preview."
  @variable ~r/\{\{\s*([a-z_]+)\s*\}\}/
  def merge(template, variables) do
    missing =
      Regex.scan(@variable, template, capture: :all_but_first)
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.reject(&(is_binary(variables[&1]) and String.trim(variables[&1]) != ""))

    if missing == [],
      do: {:ok, Regex.replace(@variable, template, fn _, key -> variables[key] end)},
      else: {:error, missing}
  end

  def html(source) do
    MDEx.to_html!(source,
      render: [escape: true],
      sanitize: [
        rm_tags: ["img", "area", "map"],
        url_schemes: ["https", "http", "mailto"],
        url_relative: :deny
      ]
    )
  end
end
