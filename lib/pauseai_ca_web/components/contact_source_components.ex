defmodule PauseAiCaWeb.ContactSourceComponents do
  @moduledoc "Consumer-owned source metadata shared by contact lists, profiles and import previews."
  use PauseAiCaWeb, :html

  attr :id, :string, required: true
  attr :data, :map, required: true

  def source_summary(assigns) do
    assigns = assign(assigns, :geography, source_geography(assigns.data))

    ~H"""
    <dl id={@id} class="mt-2 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2 xl:grid-cols-4">
      <div>
        <dt class="font-normal text-stone-600">{gettext("Signup date")}</dt>
        <dd class="break-words font-medium text-stone-900">
          {source_summary_value(@data, "signup_date")}
        </dd>
      </div>
      <div>
        <dt class="font-normal text-stone-600">{gettext("Geography")}</dt>
        <dd class="break-words font-medium text-stone-900">
          {elem(@geography, 0)}<span :if={elem(@geography, 1)} class="block text-xs text-stone-600">{elem(
            @geography,
            1
          )}</span>
        </dd>
      </div>
      <div :for={field <- ~w(source sheet source_status status welcomed_date)}>
        <dt class="font-normal text-stone-600">{field_label(field)}</dt>
        <dd class="break-words font-medium text-stone-900">{source_summary_value(@data, field)}</dd>
      </div>
    </dl>
    """
  end

  attr :id, :string, required: true
  attr :data, :map, required: true

  def source_details(assigns) do
    ~H"""
    <details id={@id} class="mt-3 text-sm text-stone-600">
      <summary class="cursor-pointer font-semibold text-stone-800">
        {gettext("Show imported source fields")}
      </summary>
      <dl class="mt-3 grid gap-x-6 gap-y-2 sm:grid-cols-2 lg:grid-cols-3">
        <div :for={{field, value} <- Enum.sort(@data)}>
          <dt class="font-normal text-stone-600">{field_label(field)}</dt>
          <dd class="break-words text-stone-900">
            {if is_map(value) or is_list(value), do: Jason.encode!(value), else: value}
          </dd>
        </div>
      </dl>
    </details>
    """
  end

  defp source_summary_value(data, field) do
    value = data[field]
    value = if field == "signup_date" and value in [nil, ""], do: data["signup"], else: value

    cond do
      value in [nil, ""] ->
        gettext("Not provided")

      field in ~w(signup_date welcomed_date) ->
        PauseAiCa.ContactMigration.HistoricalDates.source_date_display(value)

      true ->
        value
    end
  end

  defp source_geography(data) do
    region =
      Enum.find_value(~w(geography region), fn key ->
        if data[key] not in [nil, ""], do: data[key]
      end)

    if region do
      basis =
        case data["region_source"] do
          "self_reported" -> gettext("Self-reported region")
          "postal_code" -> gettext("Computed from postal code")
          "computed" -> gettext("Computed region")
          _ -> gettext("Region supplied by source")
        end

      {region, basis}
    else
      geography =
        case String.downcase(data["sheet"] || "") do
          "mtl" -> "Montréal"
          "quebec" -> "ROQuébec"
          "rest of canada" -> "ROCanada"
          _ -> nil
        end

      if geography,
        do: {geography, gettext("From source sheet")},
        else: {gettext("Not provided"), nil}
    end
  end

  def field_label("signup_date"), do: gettext("Signup date")
  def field_label("source"), do: gettext("Source")
  def field_label("sheet"), do: gettext("Sheet")
  def field_label("source_status"), do: gettext("Source status")
  def field_label("status"), do: gettext("Sheet status")
  def field_label("welcomed_date"), do: gettext("Welcomed date")

  def field_label(field),
    do: field |> String.replace("_", " ") |> String.capitalize()
end
