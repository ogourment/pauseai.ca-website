defmodule PauseAiCa.ContactMigration.Geography do
  @moduledoc "Shared source-geography normalization for rendering, import defaults and targeting."
  @regions ["Montréal", "ROQuébec", "ROCanada"]
  @sql """
  (SELECT CASE
    WHEN lower(region) IN ('montreal', 'montréal', 'mtl') THEN 'Montréal'
    WHEN region IS NOT NULL THEN region
    WHEN sheet = 'mtl' THEN 'Montréal'
    WHEN sheet = 'quebec' THEN 'ROQuébec'
    WHEN sheet = 'rest of canada' THEN 'ROCanada'
    WHEN city IN ('montreal', 'montréal', 'mtl') THEN 'Montréal'
    ELSE NULL END
   FROM (VALUES (COALESCE(NULLIF(btrim(?->>'geography'), ''), NULLIF(btrim(?->>'region'), '')),
     lower(btrim(?->>'sheet')), lower(btrim(?->>'city')))) AS geo(region, sheet, city))
  """
  def regions, do: @regions

  def resolve(data) when is_map(data) do
    cond do
      region = nonblank(data["geography"]) || nonblank(data["region"]) ->
        {normalize(region), data["region_source"] || "source"}

      sheet_region(data["sheet"]) ->
        {sheet_region(data["sheet"]), "sheet"}

      city_region(data["city"]) ->
        {city_region(data["city"]), "city"}

      true ->
        {nil, nil}
    end
  end

  def with_default(rows, value) when value in ["", nil], do: {:ok, rows}

  def with_default(rows, value) when value in @regions do
    {:ok,
     Enum.map(rows, fn row ->
       if elem(resolve(row), 0),
         do: row,
         else: Map.merge(row, %{"geography" => value, "region_source" => "upload_default"})
     end)}
  end

  def with_default(_, _), do: {:error, :invalid_geography}

  defmacro expression(data) do
    quote do
      fragment(unquote(@sql), unquote(data), unquote(data), unquote(data), unquote(data))
    end
  end

  defp normalize(value),
    do: if(String.downcase(value) in ~w(montreal montréal mtl), do: "Montréal", else: value)

  defp nonblank(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: String.trim(value))

  defp nonblank(_), do: nil

  defp city_region(value),
    do:
      if(is_binary(value) and String.downcase(String.trim(value)) in ~w(montreal montréal mtl),
        do: "Montréal"
      )

  defp sheet_region(value) do
    case if(is_binary(value), do: String.downcase(String.trim(value))) do
      "mtl" -> "Montréal"
      "quebec" -> "ROQuébec"
      "rest of canada" -> "ROCanada"
      _ -> nil
    end
  end
end
