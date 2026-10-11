defmodule PauseAiCa.Newsletters.Lists do
  @moduledoc "PauseAI geography rules over shared dynamic lists; local newsletter consent remains authoritative."
  alias PhoenixCRM.{MailingLists, ListRules}
  defp ctx, do: PhoenixCRM.new(PauseAiCa.Repo, PauseAiCa.CRM.Policy)
  def list(scope), do: MailingLists.list(ctx(), scope)
  def get(scope, id), do: MailingLists.get(ctx(), scope, id)
  def archive(scope, list), do: MailingLists.archive(ctx(), scope, list)

  def save(scope, expected, attrs) do
    with {:ok, criteria} <- criteria(attrs) do
      attrs = %{name: attrs["name"], criteria: criteria}

      if expected,
        do: MailingLists.save(ctx(), scope, expected, attrs),
        else: MailingLists.create(ctx(), scope, attrs)
    end
  end

  def form(nil), do: %{"name" => "", "match" => "any", "city" => "", "region" => "", "fsas" => ""}

  def form(list) do
    rules = Map.new(list.criteria["rules"], &{&1["field"], Enum.join(&1["values"], ", ")})

    Map.merge(form(nil), %{
      "name" => list.name,
      "match" => list.criteria["match"],
      "city" => rules["city"] || "",
      "region" => rules["region"] || "",
      "fsas" => rules["fsa"] || ""
    })
  end

  def matches?(list, subscription), do: ListRules.matches?(list.criteria, fields(subscription))

  def reasons(list, subscription),
    do: ListRules.matching_fields(list.criteria, fields(subscription))

  defp fields(s), do: %{"city" => s.city, "region" => s.region, "fsa" => s.fsa}

  defp criteria(attrs) do
    fsas = values(attrs["fsas"]) |> Enum.map(&PauseAiCa.PostalArea.normalize/1)

    rules =
      for {field, value} <- [
            {"city", values(attrs["city"])},
            {"region", values(attrs["region"])},
            {"fsa", fsas}
          ],
          value != [],
          do: %{
            "field" => field,
            "operator" => if(field == "fsa", do: "prefix", else: "equals"),
            "values" => value
          }

    criteria = %{"match" => attrs["match"] || "any", "rules" => rules}

    if ListRules.valid?(criteria) and Enum.all?(fsas, &PauseAiCa.PostalArea.valid?/1) and
         Enum.all?(values(attrs["region"]), &(&1 in ["Montréal", "ROQuébec", "ROCanada"])),
       do: {:ok, criteria},
       else: {:error, :invalid_rules}
  end

  defp values(s) when is_binary(s),
    do:
      s
      |> String.split([",", "\n"])
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

  defp values(_), do: []
end
