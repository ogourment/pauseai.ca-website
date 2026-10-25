defmodule PauseAiCa.CRM.Geography do
  @moduledoc "Canadian CRM geography adapter. This projection never changes sources, subscriptions or saved audience rules."
  import Ecto.Query
  alias PauseAiCa.{Repo, ContactMigration}
  alias PauseAiCa.CRM.ContactLink
  alias PhoenixCRM.{Address, Person, Source}
  alias PhoenixCRM.Geography, as: Shared
  @catalogue_file Path.expand("../../../priv/geography/canada.json", __DIR__)
  @external_resource @catalogue_file
  @catalogue @catalogue_file |> File.read!() |> Jason.decode!()
  @dimensions ~w(provinces cities areas fsas)

  def catalogue, do: @catalogue
  def version, do: @catalogue["version"]

  def filters(params) do
    @dimensions
    |> Map.new(fn field ->
      values = Shared.values(params[field]) |> Enum.map(&String.slice(&1, 0, 200))

      values =
        case field do
          "fsas" -> Enum.map(values, &PauseAiCa.PostalArea.normalize/1)
          "cities" -> Enum.map(values, &Shared.city(&1, @catalogue))
          "provinces" -> Enum.map(values, &(Shared.subdivision(&1, @catalogue) || &1))
          _ -> values
        end

      {field, values}
    end)
    |> Map.put("unknown", if(params["unknown"] == "true", do: "true", else: "false"))
  end

  def filter_params(filters) do
    filters |> Enum.reject(fn {_key, value} -> value in [[], "false", nil, ""] end) |> Map.new()
  end

  def matches?(geography, filters, region) do
    selected? = Shared.selected?(filters)

    (region == "" and not selected?) or
      (region != "" and region in geography.regions) or
      (selected? and Shared.matches?(geography, filters))
  end

  def project_people([]), do: %{}

  def project_people(people) do
    ids = Enum.map(people, & &1.id)

    # Canonical aliases and address-linked immutable snapshots participate together.
    # Two batched reads; no per-person activity/profile hydration and no mutation.
    shared =
      Repo.all(
        from p in Person,
          join: a in Address,
          on: a.person_id == p.id,
          join: s in Source,
          on: s.address_id == a.id,
          where: p.id in ^ids or p.canonical_id in ^ids,
          select: {p.canonical_id, p.id, s.original, s.observed_at}
      )

    legacy =
      Repo.all(
        from p in Person,
          join: link in ContactLink,
          on: link.person_id == p.id,
          join: c in ContactMigration.Contact,
          on: c.id == link.contact_id,
          where: p.id in ^ids or p.canonical_id in ^ids,
          select: {p.canonical_id, p.id, c.source_data, c.inserted_at, c.city}
      )

    facts =
      Enum.map(shared, fn {canonical, id, data, at} -> {canonical || id, facts(data), at} end) ++
        Enum.map(legacy, fn {canonical, id, data, at, city} ->
          {canonical || id, facts(Map.put_new(data, "city", city)), at}
        end)

    grouped =
      facts
      |> Enum.sort_by(fn {_, _, at} -> at end, {:desc, DateTime})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Map.new(people, fn person ->
      sources = Map.get(grouped, person.id, [])
      projection = Shared.project(%{"city" => person.city}, sources, @catalogue)

      regions =
        sources |> Enum.map(& &1["recorded_region"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      {person.id, Map.put(projection, :regions, regions)}
    end)
  end

  def subdivision_name(nil), do: nil

  def subdivision_name(code),
    do:
      Enum.find_value(@catalogue["subdivisions"], fn row ->
        if row["id"] == code, do: row["name"]
      end)

  defp facts(data) when is_map(data) do
    {region, _} = ContactMigration.Geography.resolve(data)
    city = fact_value(data, ~w(city City)) || if(region == "Montréal", do: region)

    %{
      "city" => city,
      "subdivision" =>
        fact_value(data, ~w(province province_code state subdivision)) ||
          Shared.subdivision(region, @catalogue),
      "postal_area" => fact_value(data, ~w(fsa FSA postal_area postal_code postalCode)),
      "country" => fact_value(data, ~w(country Country)),
      "recorded_region" => region
    }
  end

  defp fact_value(data, keys),
    do:
      Enum.find_value(keys, fn key ->
        case data[key] do
          value when is_binary(value) -> if String.trim(value) != "", do: String.trim(value)
          _ -> nil
        end
      end)
end
