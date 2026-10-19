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

  attr :query, :string, default: ""

  def source_details(assigns) do
    ~H"""
    <details id={@id} class="mt-3 text-sm text-stone-600">
      <summary class="cursor-pointer font-semibold text-stone-800">
        {gettext("Show imported source fields")}
      </summary>
      <dl class="mt-3 grid gap-x-6 gap-y-2 sm:grid-cols-2 lg:grid-cols-3">
        <div
          :for={{field, value} <- Enum.sort(@data)}
          class={
            if PhoenixCRM.SourceMetadata.format_json(value),
              do: "min-w-0 sm:col-span-2 lg:col-span-3",
              else: "min-w-0"
          }
        >
          <dt class="font-normal text-stone-600">{field_label(field)}</dt>
          <dd class="break-words text-stone-900">
            <pre
              :if={PhoenixCRM.SourceMetadata.format_json(value)}
              class="mt-1 max-w-full overflow-x-auto whitespace-pre-wrap break-words rounded-lg border border-stone-200 bg-stone-50 p-3 text-xs"
            ><code><.highlight text={PhoenixCRM.SourceMetadata.format_json(value)} query={@query} /></code></pre>
            <span :if={!PhoenixCRM.SourceMetadata.format_json(value)}><.highlight
              text={to_string(if(is_nil(value), do: "", else: value))}
              query={@query}
            /></span>
          </dd>
        </div>
      </dl>
    </details>
    """
  end

  attr :data, :map, required: true
  attr :query, :string, default: ""

  def source_matches(assigns) do
    assigns =
      assign(assigns, :matches, PhoenixCRM.SourceMetadata.matches(assigns.data, assigns.query))

    ~H"""
    <ul
      :if={@matches != []}
      class="my-2 space-y-1 rounded border-l-4 border-amber-500 bg-amber-50 px-3 py-2 text-sm text-stone-900"
      data-source-search-matches
    >
      <li :for={match <- @matches} class="break-words">
        <strong>{gettext("Matched source field")}: </strong><code class="break-all"><.highlight
          text={match.path}
          query={@query}
        /></code>
        · <.highlight text={match.excerpt} query={@query} />
      </li>
    </ul>
    """
  end

  attr :text, :string, required: true
  attr :query, :string, default: ""

  defp highlight(assigns) do
    assigns =
      assign(assigns, :chunks, PhoenixCRM.SourceMetadata.chunks(assigns.text, assigns.query))

    ~H"""
    <span :for={{matched?, text} <- @chunks}><mark
      :if={matched?}
      class="rounded bg-amber-200 text-stone-950"
    >{text}</mark><span :if={!matched?}>{text}</span></span>
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
