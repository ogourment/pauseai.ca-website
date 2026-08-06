defmodule Mix.Tasks.I18n.Check do
  @shortdoc "Check Gettext catalog completeness and locale display-copy branches"
  use Mix.Task

  @locales ~w(en fr)
  @domains ~w(default errors)

  @impl Mix.Task
  def run(_args) do
    issues = catalog_issues() ++ hardcoded_copy_issues()

    if issues == [] do
      Mix.shell().info("Gettext catalogs and display copy are complete.")
    else
      Enum.each(issues, fn issue -> Mix.shell().error(issue) end)
      Mix.raise("#{length(issues)} i18n issue(s) found")
    end
  end

  defp catalog_issues do
    for domain <- @domains,
        locale <- @locales,
        issue <- compare_catalog(domain, locale),
        do: issue
  end

  defp compare_catalog(domain, locale) do
    template = parse!("priv/gettext/#{domain}.pot")
    catalog = parse!("priv/gettext/#{locale}/LC_MESSAGES/#{domain}.po")
    template_keys = template |> active() |> MapSet.new(&Expo.Message.key/1)
    catalog_by_key = catalog |> active() |> Map.new(&{Expo.Message.key(&1), &1})

    missing =
      template_keys
      |> Enum.reject(&Map.has_key?(catalog_by_key, &1))
      |> Enum.map(&"Missing translation [#{locale}/#{domain}]: #{inspect(&1)}")

    invalid =
      for {key, message} <- catalog_by_key,
          issue <- message_issues(message, key, template_keys, locale, domain),
          do: issue

    obsolete =
      for message <- catalog.messages,
          message.obsolete,
          do: "Obsolete translation [#{locale}/#{domain}]: #{inspect(Expo.Message.key(message))}"

    missing ++ invalid ++ obsolete
  end

  defp message_issues(message, key, template_keys, locale, domain) do
    prefix = "[#{locale}/#{domain}]: #{inspect(key)}"

    []
    |> maybe_add(not MapSet.member?(template_keys, key), "Stale translation #{prefix}")
    |> maybe_add(Expo.Message.has_flag?(message, "fuzzy"), "Fuzzy translation #{prefix}")
    |> maybe_add(blank?(message), "Blank translation #{prefix}")
  end

  defp parse!(path), do: path |> Expo.PO.parse_file!()
  defp active(po), do: Enum.reject(po.messages, & &1.obsolete)
  defp blank?(%Expo.Message.Singular{msgstr: value}), do: IO.iodata_length(value) == 0

  defp blank?(%Expo.Message.Plural{msgstr: values}),
    do: values == %{} or Enum.any?(values, &(IO.iodata_length(elem(&1, 1)) == 0))

  defp maybe_add(issues, true, issue), do: [issue | issues]
  defp maybe_add(issues, false, _issue), do: issues

  defp hardcoded_copy_issues do
    patterns = [~r/if\(?@locale == "fr"/, ~r/if\(socket\.assigns\.locale == "fr"/]

    for file <- Path.wildcard("lib/**/*.{ex,heex}"),
        lines = File.read!(file) |> String.split("\n"),
        {line, number} <- Enum.with_index(lines, 1),
        Enum.any?(patterns, &Regex.match?(&1, line)),
        context = Enum.slice(lines, max(number - 3, 0), 6) |> Enum.join("\n"),
        not route_or_data_branch?(context),
        do: "Hardcoded locale display copy at #{file}:#{number}"
  end

  defp route_or_data_branch?(line) do
    String.contains?(line, ["href=", "navigate=", "translated_path=", "source="])
  end
end
