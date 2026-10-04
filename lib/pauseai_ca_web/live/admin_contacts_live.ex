defmodule PauseAiCaWeb.AdminContactsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{CRM, Volunteers}
  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.superadmin?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Contacts"),
         records: [],
         directory_origins: %{},
         record: nil,
         origins: [],
         activities: [],
         comparison: nil,
         candidates: [],
         reconciling: false,
         merges: [],
         error: nil,
         status: nil,
         form: to_form(%{}, as: "contact"),
         search: ""
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Superadmin access required."))
       |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    scope = socket.assigns.current_scope

    result =
      cond do
        params["legacy_id"] -> CRM.get_legacy(scope, params["legacy_id"])
        params["id"] -> CRM.get(scope, params["id"])
        true -> :directory
      end

    case result do
      {:ok, record} ->
        {:noreply, load_record(socket, record)}

      :directory ->
        with {:ok, records} <- CRM.search(scope, params["q"] || ""),
             {:ok, origins} <- CRM.directory_origins(scope, records) do
          {:noreply,
           assign(socket,
             record: nil,
             records: records,
             directory_origins: origins,
             search: params["q"] || ""
           )}
        else
          _ -> {:noreply, denied(socket)}
        end

      _ ->
        {:noreply, denied(socket)}
    end
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket),
    do:
      {:noreply,
       push_patch(socket, to: ~p"/admin/contacts?#{%{locale: socket.assigns.locale, q: term}}")}

  def handle_event("edit", %{"contact" => attrs}, socket),
    do: {:noreply, assign(socket, form: to_form(attrs, as: "contact"), status: nil)}

  def handle_event("save", %{"contact" => attrs}, socket) do
    case CRM.update(socket.assigns.current_scope, socket.assigns.record, attrs) do
      {:ok, record} ->
        {:noreply, socket |> load_record(record) |> assign(status: gettext("Saved"))}

      _ ->
        {:noreply,
         assign(socket,
           error: gettext("Contact changed or access was revoked. Reload before saving.")
         )}
    end
  end

  def handle_event("reconcile", _, socket) do
    case CRM.search(socket.assigns.current_scope, "") do
      {:ok, records} ->
        {:noreply,
         assign(socket,
           reconciling: true,
           comparison: nil,
           error: nil,
           candidates: Enum.reject(records, &(&1.person.id == socket.assigns.record.person.id))
         )}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  def handle_event("compare", %{"comparison" => %{"other" => id}}, socket) do
    case CRM.compare(socket.assigns.current_scope, socket.assigns.record.person.id, id) do
      {:ok, comparison} -> {:noreply, assign(socket, comparison: comparison, error: nil)}
      _ -> {:noreply, assign(socket, error: gettext("Choose another available person."))}
    end
  end

  def handle_event("merge", %{"resolution" => attrs}, socket) do
    attrs = Map.reject(attrs, fn {_, value} -> value == "" end)

    case CRM.merge(socket.assigns.current_scope, socket.assigns.comparison, attrs) do
      {:ok, %{record: record}} ->
        {:noreply,
         socket
         |> load_record(record)
         |> assign(comparison: nil, reconciling: false, status: gettext("Reconciliation saved"))}

      _ ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "Choose every conflicting field and a preferred address. Reload if the records changed."
             )
         )}
    end
  end

  def handle_event("undo", %{"id" => id}, socket) do
    case CRM.undo(socket.assigns.current_scope, id) do
      {:ok, _} ->
        {:ok, record} = CRM.get(socket.assigns.current_scope, socket.assigns.record.person.id)

        {:noreply,
         socket |> load_record(record) |> assign(status: gettext("Reconciliation undone"))}

      _ ->
        {:noreply,
         assign(socket,
           error: gettext("This person changed after reconciliation. Undo is no longer safe.")
         )}
    end
  end

  defp load_record(socket, record) do
    scope = socket.assigns.current_scope
    legacy = CRM.legacy_activities(scope, record.person.id)
    activities = record.activities ++ legacy
    # Sort DateTimes explicitly; UUID is a deterministic tie breaker.
    activities =
      Enum.sort(activities, fn a, b ->
        case DateTime.compare(a.inserted_at, b.inserted_at) do
          :eq -> a.id >= b.id
          :gt -> true
          :lt -> false
        end
      end)

    assign(socket,
      record: record,
      origins: CRM.origins(scope, record.person.id),
      activities: activities,
      merges: CRM.merges(scope, record.person.id),
      form:
        to_form(%{"name" => record.person.name || "", "city" => record.person.city || ""},
          as: "contact"
        ),
      error: nil
    )
  end

  defp historical_date_label("source_created"), do: gettext("Original source record created")

  defp historical_date_label("notification_sent"),
    do: gettext("Original global notification sent")

  defp historical_date_label("first_known_processing"),
    do: gettext("Earliest recovered processing; earlier runs may exist")

  defp historical_date_label("signup_date"), do: gettext("Source signup / date added")

  defp historical_date_label("processed_at"),
    do: gettext("Latest source processing; overwritten by later runs")

  defp historical_source_label("notion"), do: "Notion"
  defp historical_source_label("google_sheet"), do: "Google Sheets"
  defp historical_source_label("pauseai_global_email"), do: gettext("PauseAI Global email")
  defp historical_source_label("pauseai_automations"), do: gettext("PauseAI Automations")
  defp historical_source_label(source), do: source

  defp denied(socket),
    do:
      socket
      |> put_flash(:error, gettext("Contact unavailable."))
      |> push_navigate(to: ~p"/dashboard")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      active_tab="contacts"
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
    >
      <main class="mx-auto max-w-5xl px-5 py-10 crm-surface">
        <h1 class="text-3xl font-bold mb-6">{gettext("Contacts")}</h1>
        <p :if={@error} id="crm-error" role="alert" class="crm-error">{@error}</p>
        <p :if={@status} role="status">{@status}</p>
        <section :if={is_nil(@record)} id="crm-directory">
          <.form
            id="crm-search-form"
            for={to_form(%{"search" => @search})}
            phx-change="search"
            phx-submit="search"
          >
            <.input
              id="crm-search"
              name="search"
              value={@search}
              type="search"
              label={gettext("Find a contact")}
              phx-debounce="250"
            />
          </.form>
          <p>
            {gettext(
              "Historical contacts are private. Importing or reconciling them does not create an account or consent."
            )}
          </p>
          <ul>
            <li :for={record <- @records} id={"crm-contact-#{record.person.id}"} class="py-4 border-b">
              <strong>{record.person.name}</strong><div :for={address <- record.addresses}>
                <.link navigate={~p"/admin/contacts/#{record.person.id}?locale=#{@locale}"}>{address.email}</.link>
              </div>
              <div :for={origin <- Map.get(@directory_origins, record.person.id, [])} class="mt-4">
                <p class="text-sm font-semibold text-stone-700">{origin.email}</p>
                <PauseAiCaWeb.ContactSourceComponents.source_summary
                  id={"directory-source-summary-#{origin.id}"}
                  data={origin.source_data}
                />
              </div>
            </li>
          </ul>
        </section>
        <section :if={@record} id="crm-record">
          <.form
            for={@form}
            id="crm-contact-form"
            phx-change="edit"
            phx-submit="save"
            class="space-y-4"
          >
            <.input field={@form[:name]} label={gettext("Name")} /><.input
              field={@form[:city]}
              label={gettext("City")}
            />
            <button class="crm-button" phx-disable-with={gettext("Saving…")}>{gettext("Save contact")}</button>
          </.form>
          <section id="crm-addresses" class="mt-8">
            <h2 class="text-xl font-bold">{gettext("Addresses")}</h2><ul>
              <li :for={address <- @record.addresses}>
                {address.email}<span :if={address.id == @record.person.preferred_address_id}> · {gettext(
                  "Preferred"
                )}</span>
              </li>
            </ul><p>
              {gettext("A preferred address does not grant permission to contact this person.")}
            </p>
          </section>
          <section id="crm-origins" class="mt-8">
            <h2 class="text-xl font-bold">{gettext("Origins and preserved links")}</h2><ul>
              <li :for={source <- @record.sources}>{source.source} · {source.external_key}</li><li :for={
                origin <- @origins
              }>
                <.link navigate={~p"/admin/contacts/legacy/#{origin.id}?locale=#{@locale}"}>{origin.email}</.link>
                · {origin.classification} · {origin.source}
              </li>
            </ul>
          </section>
          <section :if={@origins != []} id="crm-source-details" class="mt-8">
            <h2 class="text-xl font-bold">{gettext("Source")}</h2>
            <div :for={origin <- @origins} class="mt-4 border-b border-stone-200 pb-4">
              <h3 class="font-semibold break-all">{origin.email}</h3>
              <PauseAiCaWeb.ContactSourceComponents.source_summary
                id={"profile-source-summary-#{origin.id}"}
                data={origin.source_data}
              />
              <details class="mt-3 text-sm text-stone-600">
                <summary class="cursor-pointer font-semibold text-stone-800">
                  {gettext("Show imported source fields")}
                </summary>
                <dl class="mt-3 grid gap-x-6 gap-y-2 sm:grid-cols-2 lg:grid-cols-3">
                  <div :for={{field, value} <- Enum.sort(origin.source_data)}>
                    <dt class="font-semibold">
                      {PauseAiCaWeb.ContactSourceComponents.field_label(field)}
                    </dt>
                    <dd class="break-words">
                      {if is_map(value) or is_list(value), do: Jason.encode!(value), else: value}
                    </dd>
                  </div>
                </dl>
              </details>
            </div>
          </section>
          <section id="crm-historical-dates" class="mt-8">
            <h2 class="text-xl font-bold">{gettext("Historical source dates")}</h2>
            <p>
              {gettext(
                "Source creation, notification and processing times describe different events. Migration activity below records this database's import time."
              )}
            </p>
            <ul :for={origin <- @origins}>
              <li :for={
                date <- PauseAiCa.ContactMigration.HistoricalDates.entries(origin.source_data)
              }>
                <strong>{historical_date_label(date["kind"])}</strong>
                ·
                <time datetime={date["value"]}>{PauseAiCa.ContactMigration.HistoricalDates.display_value(
                  date
                )}</time>
                <span :if={date["precision"] == "date"}> · {gettext("Date only; time unknown")}</span>
                <span :if={
                  date["precision"] == "datetime" and
                    date["timezone"] not in ["UTC", "explicit offset"]
                }> · {gettext("Timezone unknown")}</span>
                · {historical_source_label(date["source"])}
                <span :if={date["source_record_id"]}> · {date["source_record_id"]}</span>
              </li>
            </ul>
          </section>
          <section id="crm-activity" class="mt-8">
            <h2 class="text-xl font-bold">{gettext("Activity")}</h2><ul>
              <li :for={activity <- @activities}>
                <time datetime={DateTime.to_iso8601(activity.inserted_at)}>{Calendar.strftime(
                  activity.inserted_at,
                  "%Y-%m-%d %H:%M UTC"
                )}</time>
                · {activity.action}
              </li>
            </ul>
          </section>
          <section class="mt-8">
            <button type="button" phx-click="reconcile" class="crm-button">{gettext("Reconcile")}</button>
            <.form
              :if={@reconciling}
              for={to_form(%{}, as: "comparison")}
              phx-submit="compare"
              class="mt-4 space-y-4"
            >
              <.input
                type="select"
                id="crm-other-person"
                name="comparison[other]"
                value=""
                label={gettext("Other person")}
                prompt={gettext("Choose a person")}
                options={Enum.map(@candidates, fn r -> {hd(r.addresses).email, r.person.id} end)}
              /><button class="crm-button">{gettext("Compare")}</button>
            </.form>
            <.form
              :if={@comparison}
              for={to_form(%{}, as: "resolution")}
              id="crm-comparison"
              phx-submit="merge"
              class="mt-4 space-y-4"
            >
              <p>{gettext("Comparison is read-only. Confirm your choices to reconcile.")}</p>
              <p :for={{field, values} <- @comparison.conflicts}>
                <strong>{if field == "city", do: gettext("City"), else: gettext("Name")}:</strong>
                {values.left || "—"} · {values.right || "—"}
              </p>
              <.input
                :for={{field, values} <- @comparison.conflicts}
                type="select"
                id={"crm-resolution-#{field}"}
                name={"resolution[#{field}]"}
                value=""
                label={if field == "city", do: gettext("City"), else: gettext("Name")}
                prompt={gettext("Choose a value")}
                options={[values.left, values.right]}
              />
              <.input
                type="select"
                id="crm-preferred-address"
                name="resolution[preferred_address_id]"
                value=""
                label={gettext("Preferred address")}
                prompt={gettext("Choose an address")}
                options={
                  Enum.map(
                    @comparison.left.addresses ++ @comparison.right.addresses,
                    &{&1.email, &1.id}
                  )
                }
              />
              <button class="crm-button">{gettext("Confirm reconciliation")}</button>
            </.form>
            <div :for={merge <- @merges} :if={is_nil(merge.undone_at)} class="mt-4">
              <button type="button" phx-click="undo" phx-value-id={merge.id} class="crm-button">{gettext(
                "Undo reconciliation"
              )}</button>
            </div>
          </section>
        </section>
      </main>
    </Layouts.management>
    """
  end
end
