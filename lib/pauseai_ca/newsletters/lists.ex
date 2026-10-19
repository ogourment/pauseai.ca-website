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

  def form(nil), do: Map.put(PhoenixCRM.AreaRules.form(nil), "name", "")
  def form(list), do: Map.put(PhoenixCRM.AreaRules.form(list.criteria), "name", list.name)

  # GTA municipalities and common Toronto borough city values; consumer-owned.
  # No ROCanada rule or guessed postal coverage.
  def preset("toronto") do
    Map.merge(form(nil), %{
      "name" => "Toronto / GTA",
      "city" =>
        "Toronto, North York, Scarborough, Etobicoke, East York, York, Ajax, Brock, Clarington, Oshawa, Pickering, Scugog, Uxbridge, Whitby, Burlington, Halton Hills, Milton, Oakville, Brampton, Caledon, Mississauga, Aurora, East Gwillimbury, Georgina, King, Markham, Newmarket, Richmond Hill, Vaughan, Whitchurch-Stouffville"
    })
  end

  def preset("montreal"),
    do:
      Map.merge(form(nil), %{"name" => "Montréal", "city" => "Montréal", "region" => "Montréal"})

  def preset(_), do: form(nil)

  def matches?(list, subscription), do: ListRules.matches?(list.criteria, fields(subscription))

  def reasons(list, subscription),
    do: ListRules.matching_fields(list.criteria, fields(subscription))

  defp fields(s), do: %{"city" => s.city, "region" => s.region, "fsa" => s.fsa}

  defp criteria(attrs),
    do:
      PhoenixCRM.AreaRules.criteria(attrs,
        normalize_postal: &PauseAiCa.PostalArea.normalize/1,
        valid_postal?: &PauseAiCa.PostalArea.valid?/1
      )
end
