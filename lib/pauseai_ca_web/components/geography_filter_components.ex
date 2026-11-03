defmodule PauseAiCaWeb.GeographyFilterComponents do
  use PauseAiCaWeb, :html

  attr :id, :string, required: true
  attr :name, :string, default: nil
  attr :class, :string, default: nil
  attr :filters, :map, required: true
  attr :cities, :list, default: []

  def geography_filters(assigns) do
    ~H"""
    <div class={["grid min-w-0 gap-3 sm:grid-cols-2", @class]}>
      <input type="hidden" name={field_name(@name, "provinces") <> "[]"} value="" />
      <.input
        type="select"
        multiple
        id={@id <> "-provinces"}
        class="block w-full min-w-0 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-base-content"
        name={field_name(@name, "provinces") <> "[]"}
        value={@filters["provinces"]}
        label={gettext("Provinces and territories")}
        options={
          Enum.map(
            PauseAiCa.CRM.Geography.catalogue()["subdivisions"],
            &{province_label(&1["id"]), &1["id"]}
          )
        }
      />
      <input type="hidden" name={field_name(@name, "cities") <> "[]"} value="" />
      <.input
        type="select"
        multiple
        id={@id <> "-cities"}
        class="block w-full min-w-0 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-base-content"
        name={field_name(@name, "cities") <> "[]"}
        value={@filters["cities"]}
        label={gettext("Cities")}
        options={
          Enum.uniq(
            @cities ++
              Enum.map(PauseAiCa.CRM.Geography.catalogue()["cities"], & &1["name"]) ++
              @filters["cities"]
          )
          |> Enum.sort()
          |> Enum.map(&{&1, &1})
        }
      />
      <input type="hidden" name={field_name(@name, "areas") <> "[]"} value="" />
      <.input
        type="select"
        multiple
        id={@id <> "-areas"}
        class="block w-full min-w-0 rounded-lg border border-base-300 bg-base-100 px-3 py-2 text-base-content"
        name={field_name(@name, "areas") <> "[]"}
        value={@filters["areas"]}
        label={gettext("Named areas")}
        options={Enum.map(PauseAiCa.CRM.Geography.catalogue()["areas"], &{&1["name"], &1["id"]})}
      />
      <.input
        id={@id <> "-fsas"}
        name={field_name(@name, "fsas")}
        value={Enum.join(@filters["fsas"], ", ")}
        label={gettext("FSA (first three postal-code characters)")}
        placeholder="H2X"
      />
      <.input
        type="checkbox"
        id={@id <> "-unknown-geography"}
        name={field_name(@name, "unknown")}
        value="true"
        checked={@filters["unknown"] == "true"}
        label={gettext("Include contacts without a city, province or FSA")}
      />
      <p class="sm:col-span-2 text-sm" id={@id <> "-geography-help"}>
        {gettext(
          "Geographic selections match any selected province, city, named area or FSA (OR). Separate FSAs with commas, for example H2X, H2Y."
        )}
        {gettext(
          "Toronto / GTA uses the listed municipalities; Vancouver means the city. Unknown places are not assigned to a city or province."
        )}
      </p>
      <details id={@id <> "-area-definition"} class="text-sm sm:col-span-2">
        <summary>{gettext("Named area municipalities")}</summary>
        <p :for={area <- PauseAiCa.CRM.Geography.catalogue()["areas"]}>
          <strong>{area["name"]}</strong>: {Enum.join(area["cities"], ", ")}
        </p>
      </details>
    </div>
    """
  end

  defp field_name(nil, field), do: field
  defp field_name(name, field), do: name <> "[" <> field <> "]"

  defp province_label(nil), do: nil
  defp province_label("AB"), do: gettext("Alberta")
  defp province_label("BC"), do: gettext("British Columbia")
  defp province_label("MB"), do: gettext("Manitoba")
  defp province_label("NB"), do: gettext("New Brunswick")
  defp province_label("NL"), do: gettext("Newfoundland and Labrador")
  defp province_label("NS"), do: gettext("Nova Scotia")
  defp province_label("NT"), do: gettext("Northwest Territories")
  defp province_label("NU"), do: gettext("Nunavut")
  defp province_label("ON"), do: gettext("Ontario")
  defp province_label("PE"), do: gettext("Prince Edward Island")
  defp province_label("QC"), do: gettext("Quebec")
  defp province_label("SK"), do: gettext("Saskatchewan")
  defp province_label("YT"), do: gettext("Yukon")
  defp province_label(code), do: code
end
