defmodule PauseAiCaWeb.ContactSourceComponents do
  @moduledoc "Consumer-owned source metadata shared by contact lists, profiles and import previews."
  use PauseAiCaWeb, :html

  attr :id, :string, required: true
  attr :data, :map, required: true

  def source_summary(assigns) do
    assigns =
      assigns
      |> assign(:geography, source_geography(assigns.data))
      |> assign(:discord_identity, discord_identity(assigns.data))

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
      <div :if={@discord_identity}>
        <dt class="font-normal text-stone-600">Discord</dt>
        <dd class="break-words font-medium text-stone-900">{@discord_identity}</dd>
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
    {region, basis} = PauseAiCa.ContactMigration.Geography.resolve(data)

    label =
      case basis do
        "self_reported" -> gettext("Self-reported region")
        "postal_code" -> gettext("Computed from postal code")
        "computed" -> gettext("Computed region")
        "operator_confirmed" -> gettext("Confirmed region")
        "upload_default" -> gettext("From import default")
        "sheet" -> gettext("From source sheet")
        "city" -> gettext("From source city")
        _ -> gettext("Region supplied by source")
      end

    case first_recorded([data["city"], data["City"]]) do
      nil ->
        if region, do: {region, label}, else: {gettext("Not provided"), nil}

      city ->
        normalized_city = elem(PauseAiCa.ContactMigration.Geography.resolve(%{"city" => city}), 0)
        {normalized_city || city, gettext("From source city")}
    end
  end

  def discord_identity(data) do
    raw = if is_map(data["source_observation"]), do: data["source_observation"], else: %{}

    username =
      first_recorded([
        data["discord"],
        data["discord_username"],
        data["Discord"],
        raw["discord"],
        raw["discord_username"],
        raw["Discord"]
      ])

    user_id =
      first_recorded([
        data["discord_user_id"],
        data["Discord User ID"],
        raw["discord_user_id"],
        raw["Discord User ID"]
      ])

    case {username, user_id} do
      {nil, id} -> id
      {name, nil} -> name
      {name, id} -> name <> " · " <> id
    end
  end

  def first_recorded(values) do
    Enum.find_value(values, fn
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed not in ["", "—", "–", "-"], do: trimmed

      _ ->
        nil
    end)
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
