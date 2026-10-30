defmodule PauseAiCa.Blog.Markdown do
  @moduledoc "Article structure from the Markdown AST; legacy revisions remain immutable."
  @legacy_fields ~w(title summary details full)

  def edition(value, locale \\ "en")
  def edition(%{"markdown" => source} = edition, _locale) when is_binary(source), do: edition

  def edition(legacy, locale) when is_map(legacy) do
    {details, full} =
      if locale == "fr", do: {"Détails", "Article complet"}, else: {"Details", "Full article"}

    if Enum.all?(@legacy_fields, &is_binary(legacy[&1])) do
      source =
        if Enum.all?(@legacy_fields, &(legacy[&1] == "")) do
          ""
        else
          "# " <>
            escape(legacy["title"]) <>
            "\n\n" <>
            escape(legacy["summary"]) <>
            "\n\n## " <>
            details <>
            "\n\n" <>
            normalize(legacy["details"]) <>
            "\n\n## " <> full <> "\n\n" <> normalize(legacy["full"])
        end

      %{"markdown" => source}
    else
      %{"markdown" => ""}
    end
  end

  def source(edition, locale \\ "en"), do: edition(edition, locale)["markdown"]

  def payload(payload),
    do: Map.new(payload, fn {locale, value} -> {locale, edition(value, locale)} end)

  def document(edition, locale \\ "en") do
    %MDEx.Document{nodes: nodes} = MDEx.parse_document!(source(edition, locale))

    {title, nodes} =
      case nodes do
        [%MDEx.Heading{level: 1} = heading | rest] -> {text(heading), rest}
        _ -> {"", nodes}
      end

    {intro, remaining} = Enum.split_while(nodes, &(not match?(%MDEx.Heading{}, &1)))
    {sections, []} = sections(remaining, 0, %{}) |> then(fn {items, rest, _} -> {items, rest} end)
    %{title: title, intro: html(intro), sections: sections}
  end

  defp sections([], _parent, counts), do: {[], [], counts}

  defp sections([%MDEx.Heading{level: level} | _] = nodes, parent, counts)
       when level <= parent,
       do: {[], nodes, counts}

  defp sections([%MDEx.Heading{level: level} = heading | rest], parent, counts) do
    title = text(heading)
    slug = slug(title)
    id = unique_id(slug, counts, 1)
    counts = Map.put(counts, id, true)
    {body, rest} = Enum.split_while(rest, &(not match?(%MDEx.Heading{}, &1)))
    {open?, body} = expansion(body)
    {children, rest, counts} = sections(rest, level, counts)

    section = %{
      id: id,
      title: title,
      level: level,
      open?: open?,
      html: html(body),
      sections: children
    }

    {siblings, rest, counts} = sections(rest, parent, counts)
    {[section | siblings], rest, counts}
  end

  # Only the first body block can set a section default. Code fences, quotations,
  # inline comments and later comments remain ordinary authored content.
  defp expansion([%MDEx.HtmlBlock{literal: literal} | rest] = body) do
    case String.trim(literal) do
      "<!-- open -->" -> {true, rest}
      "<!-- closed -->" -> {false, rest}
      _ -> {false, body}
    end
  end

  defp expansion(body), do: {false, body}

  # Each old field was parsed separately. Normalize it independently so an unclosed
  # fence or a reference definition cannot consume the following field on conversion.
  defp normalize(source), do: source |> MDEx.parse_document!() |> MDEx.to_markdown!()

  defp html(nodes),
    do: %MDEx.Document{nodes: nodes} |> MDEx.to_markdown!() |> PauseAiCa.Mail.Render.html()

  defp text(%{nodes: nodes}), do: Enum.map_join(nodes, &text/1)
  defp text(%{literal: literal}), do: literal
  defp text(_), do: " "

  defp slug(title) do
    value =
      title |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, "-") |> String.trim("-")

    if value == "", do: "section", else: value
  end

  defp unique_id(slug, used, number) do
    candidate = slug <> if(number == 1, do: "", else: "-#{number}")
    if Map.has_key?(used, candidate), do: unique_id(slug, used, number + 1), else: candidate
  end

  defp escape(text), do: String.replace(text, ~r/([\\`*_{}\[\]<>()#+.!|~-])/, "\\\\\\1")
end
