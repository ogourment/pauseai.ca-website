defmodule PauseAiCaWeb.AdminContactImportLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.{ContactMigration, Volunteers}
  alias PauseAiCa.ContactMigration.{CSV, Geography}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Contact imports"))
     |> assign(:preview_rows, [])
     |> assign(:preview_filename, nil)
     |> assign(:preview_source, "legacy-sheet")
     |> assign(:preview_geography, "")
     |> assign(:geography_error, nil)
     |> assign(:unknown_columns, [])
     |> assign(:selection_error, nil)
     |> assign(:selected, MapSet.new())
     |> assign(:preview_search, "")
     |> assign(:preview_page, 1)
     |> assign(:preview_page_size, 25)
     |> assign(:contact_search, "")
     |> assign(:receipt_id, nil)
     |> assign(:receipt, nil)
     |> assign(:receipts, [])
     |> assign_contact_page(%{entries: [], page: 1, page_size: 25, pages: 1, total: 0})
     |> assign(:expanded_contact_id, nil)
     |> assign(:activities, [])
     |> allow_upload(:contacts_csv,
       accept: ~w(.csv text/csv),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    search = params |> Map.get("q", "") |> String.trim()
    size = page_size(Map.get(params, "per", "25"))
    page = positive_integer(Map.get(params, "page", "1"), 1)

    {:noreply,
     socket
     |> assign(:receipt_id, empty_to_nil(params["import"]))
     |> assign(:contact_search, search)
     |> assign(:contact_page_size, size)
     |> assign(:contact_page, page)
     |> load_contact_page()}
  end

  @impl true
  def handle_event(event, params, socket) do
    if Volunteers.superadmin?(socket.assigns.current_scope),
      do: dispatch_event(event, params, socket),
      else: {:noreply, denied(socket)}
  end

  defp dispatch_event("validate-upload", _params, socket), do: {:noreply, socket}

  defp dispatch_event("preview", %{"import" => params}, socket) do
    source = normalize_source(params["source"])
    socket = assign(socket, preview_geography: params["geography"] || "", geography_error: nil)

    case Geography.with_default([], socket.assigns.preview_geography) do
      {:ok, _} ->
        results =
          consume_uploaded_entries(socket, :contacts_csv, fn %{path: path}, entry ->
            {:ok, {entry.client_name, File.read!(path)}}
          end)

        case results do
          [{filename, contents}] -> preview(socket, filename, source, contents)
          [] -> {:noreply, put_flash(socket, :error, gettext("Choose a CSV file to preview."))}
        end

      {:error, _} ->
        {:noreply, assign(socket, geography_error: gettext("Choose a valid geography."))}
    end
  end

  defp dispatch_event("search-preview", %{"search" => search}, socket),
    do:
      {:noreply,
       socket |> assign(:preview_search, String.trim(search)) |> assign(:preview_page, 1)}

  defp dispatch_event("preview-page-size", %{"page_size" => size}, socket),
    do:
      {:noreply,
       socket |> assign(:preview_page_size, page_size(size)) |> assign(:preview_page, 1)}

  defp dispatch_event("preview-page", %{"page" => page}, socket),
    do: {:noreply, assign(socket, :preview_page, positive_integer(page, 1))}

  defp dispatch_event("toggle-row", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, id),
        do: MapSet.delete(socket.assigns.selected, id),
        else: MapSet.put(socket.assigns.selected, id)

    {:noreply, socket |> assign(:selected, selected) |> assign(:selection_error, nil)}
  end

  defp dispatch_event("select-visible", _params, socket) do
    ids =
      socket.assigns
      |> visible_rows()
      |> Enum.filter(& &1["valid"])
      |> Enum.map(& &1["id"])

    {:noreply,
     socket
     |> assign(:selected, Enum.reduce(ids, socket.assigns.selected, &MapSet.put(&2, &1)))
     |> assign(:selection_error, nil)}
  end

  defp dispatch_event("clear-selection", _params, socket),
    do: {:noreply, socket |> assign(:selected, MapSet.new()) |> assign(:selection_error, nil)}

  defp dispatch_event("import-selected", params, socket) do
    selected = MapSet.new(List.wrap(params["selected"]))

    rows =
      Enum.filter(
        socket.assigns.preview_rows,
        &(&1["valid"] and MapSet.member?(selected, &1["id"]))
      )

    if rows == [] do
      {:noreply, assign(socket, :selection_error, gettext("Select at least one valid contact."))}
    else
      actor = socket.assigns.current_scope.user

      case ContactMigration.import_selected(
             rows,
             socket.assigns.preview_filename,
             socket.assigns.preview_source,
             actor
           ) do
        {:ok, %{contacts: contacts, import: receipt}} ->
          {:noreply,
           socket
           |> push_patch(
             to: ~p"/admin/contact-imports?#{%{import: receipt.id, q: "", page: 1, per: 25}}"
           )
           |> assign(:selected, MapSet.new())
           |> assign(:selection_error, nil)
           |> clear_flash(:error)
           |> put_flash(
             :info,
             ngettext(
               "Imported %{count} contact.",
               "Imported %{count} contacts.",
               length(contacts),
               count: length(contacts)
             )
           )}

        {:error, _step, _reason, _changes} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("The import could not be saved. No contacts were changed.")
           )}
      end
    end
  end

  defp dispatch_event("receipt-filter", %{"import" => id}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/admin/contact-imports?#{%{import: id, q: "", page: 1, per: socket.assigns.contact_page_size}}"
     )}
  end

  defp dispatch_event("search-contacts", %{"search" => search}, socket) do
    search = String.trim(search)

    {:noreply, patch_contact_page(socket, search, 1, socket.assigns.contact_page_size)}
  end

  defp dispatch_event("contact-page-size", %{"page_size" => size}, socket),
    do: {:noreply, patch_contact_page(socket, socket.assigns.contact_search, 1, page_size(size))}

  defp dispatch_event("contact-page", %{"page" => page}, socket),
    do:
      {:noreply,
       patch_contact_page(
         socket,
         socket.assigns.contact_search,
         positive_integer(page, 1),
         socket.assigns.contact_page_size
       )}

  defp dispatch_event("show-activity", %{"id" => id}, socket),
    do:
      {:noreply,
       socket
       |> assign(:expanded_contact_id, id)
       |> assign(:activities, ContactMigration.list_activities(id))}

  defp preview(socket, filename, source, contents) do
    with {:ok, rows, unknown_columns} <- CSV.parse(contents),
         {:ok, rows} <- Geography.with_default(rows, socket.assigns.preview_geography) do
      {:noreply,
       socket
       |> assign(:preview_rows, rows)
       |> assign(:preview_filename, filename)
       |> assign(:preview_source, source)
       |> assign(:unknown_columns, unknown_columns)
       |> assign(:selected, MapSet.new())
       |> assign(:selection_error, nil)
       |> assign(:preview_page, 1)
       |> clear_flash()}
    else
      {:error, :invalid_geography} ->
        {:noreply, put_flash(socket, :error, gettext("Choose a valid geography."))}

      {:error, :missing_email} ->
        {:noreply, put_flash(socket, :error, gettext("The CSV must contain an email column."))}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("The CSV could not be read. Check its formatting and try again.")
         )}
    end
  end

  defp normalize_source(value) do
    case String.trim(value || "") do
      "" -> "legacy-sheet"
      source -> String.slice(source, 0, 120)
    end
  end

  defp filtered_rows(rows, ""), do: rows

  defp filtered_rows(rows, search) do
    search = String.downcase(search)

    Enum.filter(rows, fn row ->
      Enum.any?(
        [row["email"], row["name"], row["city"]],
        &(is_binary(&1) and String.contains?(String.downcase(&1), search))
      )
    end)
  end

  defp visible_rows(assigns) do
    assigns.preview_rows
    |> filtered_rows(assigns.preview_search)
    |> Enum.slice(
      (assigns.preview_page - 1) * assigns.preview_page_size,
      assigns.preview_page_size
    )
  end

  defp preview_total(assigns),
    do: assigns.preview_rows |> filtered_rows(assigns.preview_search) |> length()

  defp preview_pages(assigns),
    do: max(Integer.ceil_div(preview_total(assigns), assigns.preview_page_size), 1)

  defp load_contact_page(socket) do
    scope = socket.assigns.current_scope

    case ContactMigration.contacts_page(
           scope,
           socket.assigns.contact_search,
           socket.assigns.contact_page,
           socket.assigns.contact_page_size,
           socket.assigns.receipt_id
         ) do
      {:ok, page} ->
        receipt =
          if socket.assigns.receipt_id,
            do: elem(ContactMigration.receipt(scope, socket.assigns.receipt_id), 1)

        socket
        |> assign_contact_page(page)
        |> assign(:receipt, receipt)
        |> assign(:receipts, ContactMigration.receipts(scope))

      _ ->
        denied(socket)
    end
  end

  defp denied(socket),
    do:
      socket
      |> put_flash(:error, gettext("Superadmin access required."))
      |> redirect(to: ~p"/dashboard")

  defp empty_to_nil(nil), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value) when is_binary(value), do: value
  defp empty_to_nil(_), do: "invalid"

  defp assign_contact_page(socket, page) do
    socket
    |> assign(:contacts, page.entries)
    |> assign(:contact_page, page.page)
    |> assign(:contact_page_size, page.page_size)
    |> assign(:contact_pages, page.pages)
    |> assign(:contact_total, page.total)
  end

  defp page_size(value) do
    case positive_integer(value, 25) do
      size when size in [10, 25, 50, 100] -> size
      _ -> 25
    end
  end

  defp positive_integer(value, default) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp patch_contact_page(socket, search, page, page_size) do
    push_patch(socket,
      to:
        ~p"/admin/contact-imports?#{%{q: search, page: page, per: page_size, import: socket.assigns.receipt_id || ""}}"
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management active_tab="contacts" flash={@flash} current_scope={@current_scope}>
      <section id="admin-contact-imports" class="mx-auto max-w-6xl px-5 py-16">
        <p class="eyebrow">{gettext("Superadmin")}</p>
        <h1 class="mt-3 font-heading text-5xl text-stone-950">{gettext("Contact imports")}</h1>
        <p class="mt-4 max-w-3xl text-stone-600">
          {gettext(
            "Review contacts before they enter PauseAI Canada. Importing does not send email or create accounts."
          )}
        </p>

        <section class="mt-10 rounded-3xl border border-stone-200 bg-white p-6">
          <h2 class="font-heading text-3xl text-stone-950">{gettext("Preview a CSV")}</h2>
          <.form
            id="contact-upload-form"
            for={%{}}
            as={:import}
            phx-change="validate-upload"
            phx-submit="preview"
            class="mt-6 grid gap-5 md:grid-cols-2 md:items-end"
          >
            <div>
              <label
                for={@uploads.contacts_csv.ref}
                class="block text-sm font-semibold text-stone-800"
              >{gettext("CSV file")}</label><.live_file_input
                upload={@uploads.contacts_csv}
                class="mt-2 block w-full rounded-xl border border-stone-300 p-3"
              />
            </div>
            <div>
              <label for="import-source" class="block text-sm font-semibold text-stone-800">{gettext(
                "Source label"
              )}</label><input
                id="import-source"
                name="import[source]"
                value={@preview_source}
                class="mt-2 block w-full rounded-xl border border-stone-300 p-3"
              />
            </div>
            <div>
              <label for="import-geography" class="block text-sm font-semibold text-stone-800">{gettext(
                "Default geography"
              )}</label>
              <select
                id="import-geography"
                name="import[geography]"
                aria-invalid={@geography_error != nil}
                aria-describedby={if @geography_error, do: "import-geography-error"}
                class="mt-2 w-full rounded-xl border border-stone-300 p-3"
              >
                <option value="" selected={@preview_geography == ""}>
                  {gettext("Use each row's geography or city")}
                </option>
                <option
                  :for={region <- Geography.regions()}
                  value={region}
                  selected={region == @preview_geography}
                >
                  {region}
                </option>
              </select>
              <p :if={@geography_error} id="import-geography-error" role="alert" class="crm-error">
                {@geography_error}
              </p>
              <p class="text-sm text-stone-600 mt-2">
                {gettext(
                  "Only fills missing geography. Existing regions and recognized cities are preserved."
                )}
              </p>
            </div>
            <button class="rounded-full bg-stone-900 px-5 py-3 font-semibold text-white">{gettext(
              "Preview"
            )}</button>
          </.form>
          <p class="mt-4 text-sm text-stone-600">
            {gettext(
              "Required column: Email. The 15 standard onboarding columns and 3 Montréal columns are preserved. Nothing is saved during preview."
            )}
          </p>
        </section>

        <section
          :if={@preview_filename}
          id="contact-preview"
          class="mt-8 overflow-hidden rounded-3xl border border-stone-200 bg-white"
        >
          <div class="border-b border-stone-200 p-6">
            <h2 class="font-heading text-3xl text-stone-950">{gettext("Human review")}</h2><p class="mt-2 text-stone-600">
              {gettext("%{filename}: %{count} rows found",
                filename: @preview_filename,
                count: length(@preview_rows)
              )}
            </p><p :if={@unknown_columns != []} class="mt-2 text-sm text-amber-800">
              {gettext("Additional columns preserved: %{columns}",
                columns: Enum.join(@unknown_columns, ", ")
              )}
            </p>
            <form id="preview-search-form" phx-change="search-preview" class="mt-5">
              <label for="preview-search" class="sr-only">{gettext("Search preview")}</label><input
                id="preview-search"
                name="search"
                value={@preview_search}
                phx-debounce="200"
                placeholder={gettext("Search name, email, or city")}
                class="w-full rounded-xl border border-stone-300 p-3"
              />
            </form>
            <div class="mt-4 flex flex-wrap items-center gap-3">
              <button
                phx-click="select-visible"
                class="rounded-full border border-stone-300 px-4 py-2 font-semibold"
              >{gettext("Select visible valid contacts")}</button><button
                phx-click="clear-selection"
                class="rounded-full border border-stone-300 px-4 py-2 font-semibold"
              >{gettext("Clear selection")}</button><span
                id="selected-count"
                aria-live="polite"
                class="text-sm font-semibold"
              >{ngettext("%{count} selected", "%{count} selected", MapSet.size(@selected),
                count: MapSet.size(@selected)
              )}</span>
            </div>
            <.pagination
              id="preview-pagination"
              page={@preview_page}
              pages={preview_pages(assigns)}
              total={preview_total(assigns)}
              page_size={@preview_page_size}
              page_event="preview-page"
              size_event="preview-page-size"
            />
          </div>
          <form id="contact-selection-form" phx-submit="import-selected">
            <input
              :for={id <- @selected}
              :if={id not in Enum.map(visible_rows(assigns), & &1["id"])}
              type="hidden"
              name="selected[]"
              value={id}
            />
            <div class="overflow-x-auto">
              <table class="w-full text-left">
                <thead>
                  <tr class="border-b border-stone-200">
                    <th class="p-4">{gettext("Select")}</th><th class="p-4">{gettext("Contact")}</th><th class="p-4">
                      {gettext("City")}
                    </th><th class="p-4">{gettext("Review status")}</th>
                  </tr>
                </thead><tbody :for={row <- visible_rows(assigns)}>
                  <tr
                    id={"preview-row-#{row["id"]}"}
                    class="border-b border-stone-100"
                  >
                    <td class="p-4">
                      <input
                        type="checkbox"
                        name="selected[]"
                        value={row["id"]}
                        aria-describedby={@selection_error && "selection-error"}
                        aria-label={gettext("Select %{email}", email: row["email"])}
                        checked={MapSet.member?(@selected, row["id"])}
                        disabled={!row["valid"]}
                        phx-click="toggle-row"
                        phx-value-id={row["id"]}
                      />
                    </td><td class="p-4">
                      <strong>{row["name"]}</strong><span class="block break-all text-sm text-stone-600">{row[
                        "email"
                      ]}</span>
                    </td><td class="p-4">{row["city"]}</td><td class="p-4">
                      {if row["valid"],
                        do: gettext("Ready for review"),
                        else: gettext("Invalid email — cannot select")}
                    </td>
                  </tr>
                  <tr class="border-b border-stone-100 bg-stone-50/70">
                    <td></td>
                    <td colspan="3" class="px-4 pb-4 text-sm text-stone-600">
                      <PauseAiCaWeb.ContactSourceComponents.source_summary
                        id={"preview-source-summary-#{row["id"]}"}
                        data={row}
                      />
                      <details class="mt-3">
                        <summary class="cursor-pointer font-semibold text-stone-800">
                          {gettext("Show all source fields")}
                        </summary>
                        <dl class="mt-3 grid gap-x-6 gap-y-2 sm:grid-cols-2 lg:grid-cols-3">
                          <div :for={{field, value} <- source_fields(row)}>
                            <dt class="font-semibold">{source_field_label(field)}</dt>
                            <dd class="break-words">
                              {if(value == "", do: gettext("Not provided"), else: value)}
                            </dd>
                          </div>
                        </dl>
                      </details>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div><div class="p-6">
              <p :if={@selection_error} id="selection-error" role="alert" class="mb-3 text-red-700">
                {@selection_error}
              </p>
              <button
                id="import-selected"
                type="submit"
                class="rounded-full bg-brand px-5 py-3 font-semibold text-stone-950"
              >{gettext("Import selected contacts")}</button>
            </div>
          </form>
        </section>

        <section
          id="managed-contacts"
          class="mt-8 overflow-hidden rounded-3xl border border-stone-200 bg-white"
        >
          <div class="border-b border-stone-200 p-6">
            <h2 class="font-heading text-3xl text-stone-950">{gettext("Imported contacts")}</h2>
            <form id="receipt-filter" phx-change="receipt-filter" class="mt-5">
              <label for="receipt-select" class="block text-sm font-semibold text-stone-800">{gettext(
                "Import receipt"
              )}</label>
              <select
                id="receipt-select"
                name="import"
                class="mt-2 w-full rounded-xl border border-stone-300 p-3"
              >
                <option value="" selected={is_nil(@receipt_id)}>{gettext("All imports")}</option>
                <option
                  :for={receipt <- Enum.uniq_by(List.wrap(@receipt) ++ @receipts, & &1.id)}
                  value={receipt.id}
                  selected={receipt.id == @receipt_id}
                >
                  {receipt.filename} · {receipt.source} · {Calendar.strftime(
                    receipt.inserted_at,
                    "%Y-%m-%d %H:%M UTC"
                  )} · {receipt.selected_count}
                </option>
              </select>
            </form>
            <p :if={@receipt} id="receipt-summary" class="mt-3 text-sm text-stone-600">
              {gettext("This receipt retains its observed contacts after later reimports.")}
              <.link
                patch={
                  ~p"/admin/contact-imports?#{%{import: @receipt.id, q: @contact_search, page: @contact_page, per: @contact_page_size}}"
                }
                class="underline"
              >{gettext("Link to this receipt")}</.link>
            </p>
            <form
              id="contact-search-form"
              phx-change="search-contacts"
              class="mt-5"
            >
              <label for="contact-search" class="sr-only">{gettext("Search imported contacts")}</label><input
                id="contact-search"
                name="search"
                value={@contact_search}
                phx-debounce="200"
                placeholder={gettext("Search imported contacts")}
                class="w-full rounded-xl border border-stone-300 p-3"
              />
            </form>
            <.pagination
              id="contact-pagination"
              page={@contact_page}
              pages={@contact_pages}
              total={@contact_total}
              page_size={@contact_page_size}
              page_event="contact-page"
              size_event="contact-page-size"
            />
          </div>
          <p :if={@contacts == []} class="p-6 text-stone-600">
            {gettext("No imported contacts match this search.")}
          </p>
          <ul class="divide-y divide-stone-100">
            <li :for={contact <- @contacts} id={"contact-#{contact.id}"} class="p-6">
              <div class="flex flex-wrap items-center gap-4">
                <div class="min-w-0 flex-1">
                  <strong class="break-all">{contact.email}</strong><span class="ml-3 rounded-full bg-stone-100 px-3 py-1 text-sm text-stone-700">{classification_label(
                    contact.classification
                  )}</span><span
                    :if={contact.user}
                    class="ml-3 rounded-full bg-emerald-100 px-3 py-1 text-sm text-emerald-900"
                  >{gettext("Account matched")}</span>
                </div><button
                  phx-click="show-activity"
                  phx-value-id={contact.id}
                  class="rounded-full border border-stone-300 px-4 py-2 font-semibold"
                >{gettext("View activity")}</button>
              </div>
              <PauseAiCaWeb.ContactSourceComponents.source_summary
                id={"contact-source-summary-#{contact.id}"}
                data={contact.source_data}
              />
              <PauseAiCaWeb.ContactSourceComponents.source_details
                id={"imported-source-details-#{contact.id}"}
                data={contact.source_data}
              />
              <ol :if={@expanded_contact_id == contact.id} class="mt-4 border-l-2 border-brand pl-5">
                <li :for={activity <- @activities} class="py-2">
                  <strong>{gettext("Imported")}</strong>
                  ·
                  <time datetime={DateTime.to_iso8601(activity.inserted_at)}>{Calendar.strftime(
                    activity.inserted_at,
                    "%Y-%m-%d %H:%M UTC"
                  )}</time><span class="block text-sm text-stone-600">{gettext("By %{email}",
                    email: activity.actor_user.email
                  )}</span>
                  <details
                    :if={get_in(activity.details, ["previous_observation", "source_data"])}
                    class="mt-2"
                  >
                    <summary class="cursor-pointer text-stone-600">
                      {gettext("Previous source fields preserved on replay")}
                    </summary>
                    <PauseAiCaWeb.ContactSourceComponents.source_details
                      id={"previous-observation-#{activity.id}"}
                      data={activity.details["previous_observation"]["source_data"]}
                    />
                  </details>
                  <details :if={activity.details["source_data"]} class="mt-2">
                    <summary class="cursor-pointer text-stone-600">
                      {gettext("Source observation")}
                    </summary>
                    <PauseAiCaWeb.ContactSourceComponents.source_details
                      id={"observation-#{activity.id}"}
                      data={activity.details["source_data"]}
                    />
                  </details>
                </li>
              </ol>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.management>
    """
  end

  defp classification_label("known_active"), do: gettext("Known active")
  defp classification_label("do_not_contact"), do: gettext("Do not contact")
  defp classification_label(_classification), do: gettext("Needs review")

  defp source_fields(row) do
    Enum.map(PauseAiCa.ContactMigration.CSV.source_headers(), &{&1, Map.get(row, &1, "")})
  end

  defp source_field_label(field), do: PauseAiCaWeb.ContactSourceComponents.field_label(field)

  attr :id, :string, required: true
  attr :page, :integer, required: true
  attr :pages, :integer, required: true
  attr :total, :integer, required: true
  attr :page_size, :integer, required: true
  attr :page_event, :string, required: true
  attr :size_event, :string, required: true

  defp pagination(assigns) do
    ~H"""
    <div id={@id} class="mt-4 flex flex-wrap items-center justify-between gap-3 text-sm">
      <p aria-live="polite">
        {gettext("Page %{page} of %{pages} · %{total} contacts",
          page: @page,
          pages: @pages,
          total: @total
        )}
      </p>
      <div class="flex flex-wrap items-center gap-2">
        <form id={"#{@id}-size-form"} phx-change={@size_event}>
          <label for={"#{@id}-size"} class="font-semibold">{gettext("Rows per page")}</label>
          <select
            id={"#{@id}-size"}
            name="page_size"
            class="ml-2 rounded-lg border border-stone-300 bg-white px-2 py-1"
          >
            <option :for={size <- [10, 25, 50, 100]} value={size} selected={size == @page_size}>
              {size}
            </option>
          </select>
        </form>
        <button
          type="button"
          phx-click={@page_event}
          phx-value-page={@page - 1}
          disabled={@page <= 1}
          class="rounded-full border border-stone-300 px-3 py-1 font-semibold disabled:opacity-40"
        >{gettext("Previous")}</button>
        <button
          type="button"
          phx-click={@page_event}
          phx-value-page={@page + 1}
          disabled={@page >= @pages}
          class="rounded-full border border-stone-300 px-3 py-1 font-semibold disabled:opacity-40"
        >{gettext("Next")}</button>
      </div>
    </div>
    """
  end
end
