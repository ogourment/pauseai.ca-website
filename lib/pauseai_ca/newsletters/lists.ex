defmodule PauseAiCa.Newsletters.Lists do
  @moduledoc "PauseAI geography rules over shared dynamic lists; local newsletter consent remains authoritative."
  import Ecto.Query
  alias PauseAiCa.Repo
  alias PhoenixCRM.{MailingLists, ListRules, Person, Address}
  defp ctx, do: PhoenixCRM.new(PauseAiCa.Repo, PauseAiCa.CRM.Policy)
  def list(scope), do: MailingLists.list(ctx(), scope)
  def get(scope, id), do: MailingLists.get(ctx(), scope, id)
  def archive(scope, list), do: MailingLists.archive(ctx(), scope, list)

  def save(_scope, %{criteria: %{"kind" => "static"}}, _attrs), do: {:error, :invalid_rules}

  def save(scope, expected, attrs) do
    with {:ok, geography} <- criteria(attrs),
         overrides <-
           if(expected, do: Map.take(expected.criteria, ~w(include_ids exclude_ids)), else: %{}),
         {:ok, criteria} <- ListRules.normalize_criteria(Map.merge(geography, overrides)) do
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

  @doc "Matches an entire subscription set with batched canonical contact identities; consent remains separate."
  def matching_subscriptions(scope, list, subscriptions) do
    with {:ok, criteria} <- PauseAiCa.ContactLists.canonical_criteria(scope, list.criteria) do
      emails = Enum.map(subscriptions, & &1.email)

      identities =
        if Enum.any?(~w(person_ids include_ids exclude_ids), &Map.has_key?(criteria, &1)) do
          Repo.all(
            from a in Address,
              join: p in Person,
              on: p.id == a.person_id,
              join: canonical in Person,
              on: canonical.id == fragment("COALESCE(?, ?)", p.canonical_id, p.id),
              where: a.email in ^emails,
              select: {a.email, canonical.id}
          )
          |> Map.new()
        else
          %{}
        end

      matches =
        Enum.reduce(subscriptions, {[], %{}}, fn subscription, {rows, reasons} ->
          values = Map.put(fields(subscription), "id", identities[subscription.email])

          if ListRules.matches?(criteria, values) do
            {[subscription | rows],
             Map.put(reasons, subscription.id, ListRules.matching_fields(criteria, values))}
          else
            {rows, reasons}
          end
        end)

      {Enum.reverse(elem(matches, 0)), elem(matches, 1)}
    else
      _ -> {[], %{}}
    end
  end

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
