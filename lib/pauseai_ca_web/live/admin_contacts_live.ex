defmodule PauseAiCaWeb.AdminContactsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{CRM, Volunteers}
  alias PhoenixAppShell.Selection
  @impl true
  def mount(params, session, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.superadmin?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Contacts"),
         guided_login: PauseAiCa.Assistant.GuidedMode.session_fingerprint(session["user_token"]),
         records: [],
         grid_enabled: PauseAiCaWeb.DataGridComponents.enabled?(),
         grid_revision: 0,
         grid_matched_ids: [],
         grid_total: 0,
         grid_query: %{},
         grid_geography_open: false,
         selection: Selection.new(),
         collection_lists: nil,
         invitation_ids: [],
         invitation_targets: [],
         invitation_languages: [],
         invitation_form: to_form(%{}, as: "invitation"),
         invitation_drafts: [],
         invitation_excluded: [],
         directory_origins: %{},
         creating: false,
         archived: false,
         record: nil,
         origins: [],
         activities: [],
         email_history: [],
         note_form: to_form(%{}, as: "note"),
         note_error: nil,
         note_authors: %{},
         comparison: nil,
         candidates: [],
         reconciling: false,
         merges: [],
         error: nil,
         status: nil,
         form: to_form(%{}, as: "contact"),
         search: "",
         directory_page: %{
           region: "",
           regions: [],
           geography_filters: PauseAiCa.CRM.Geography.filters(%{}),
           cities: [],
           page: 1,
           pages: 1,
           per: 25,
           total: 0
         }
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Superadmin access required."))
       |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, uri, socket) do
    socket = assign(socket, guided_params: params, guided_uri: uri)
    scope = socket.assigns.current_scope

    socket =
      assign(socket,
        search: params["q"] || socket.assigns.search,
        creating: params["new"] == "true",
        archived: params["archived"] == "true"
      )

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
        with {:ok, page} <- CRM.directory_page(scope, params),
             {:ok, origins} <- CRM.directory_origins(scope, page.records) do
          page = Map.put(page, :saved_filter_id, params["saved_filter_id"])

          selection =
            Selection.scope(
              socket.assigns.selection,
              Map.take(
                params,
                ~w(q region provinces cities areas fsas unknown archived saved_filter_id)
              )
            )

          {:noreply,
           assign(socket,
             record: nil,
             records: page.records,
             grid_revision: socket.assigns.grid_revision + 1,
             directory_page: page,
             directory_params: params,
             selection: selection,
             directory_origins: origins,
             search: page.q
           )}
        else
          _ -> {:noreply, denied(socket)}
        end

      _ ->
        {:noreply, denied(socket)}
    end
  end

  @impl true
  def handle_event("assistant-guided-observe", %{"token" => token}, socket) do
    PauseAiCa.Assistant.GuidedMode.observe(
      socket.assigns.current_scope,
      token,
      socket.assigns.guided_uri,
      socket.assigns.guided_params,
      socket.assigns.guided_login
    )

    # The observer acknowledgement precedes the next wizard action. Keep its
    # existing geography controls visible when the guided journey reaches them.
    {:noreply, assign(socket, grid_geography_open: true)}
  end

  def handle_event(
        "data_grid:query",
        %{"id" => "crm-grid", "request_id" => request_id} = payload,
        socket
      )
      when is_binary(request_id) and byte_size(request_id) <= 200 do
    case PauseAiCa.CRM.Grid.contacts(
           socket.assigns.current_scope,
           socket.assigns.directory_params,
           payload
         ) do
      {:ok, page} ->
        {:noreply,
         socket
         |> assign(
           grid_matched_ids: page.matched_ids,
           grid_total: page.total,
           grid_query: payload
         )
         |> push_event("data_grid:rows", PauseAiCa.CRM.Grid.reply(page, "crm-grid", request_id))}

      {:error, :unauthorized} ->
        {:noreply, denied(socket)}

      _ ->
        {:noreply,
         push_event(socket, "data_grid:rows", %{
           id: "crm-grid",
           request_id: request_id,
           error: true
         })}
    end
  end

  def handle_event("grid-open-selected", _, socket) do
    case Selection.ids(socket.assigns.selection) do
      [id] -> handle_event("data_grid:open_row", %{"id" => "crm-grid", "row_id" => id}, socket)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("data_grid:selection", %{"id" => "crm-grid", "ids" => ids}, socket) do
    with {:ok, canonical} <-
           PauseAiCa.ContactLists.canonical_ids(socket.assigns.current_scope, ids),
         {:ok, selection} <- Selection.select_all(Selection.new(), canonical) do
      {:noreply, assign(socket, selection: selection, invitation_ids: [])}
    else
      _ -> {:noreply, denied(socket)}
    end
  end

  def handle_event("data_grid:open_row", %{"id" => "crm-grid", "row_id" => id}, socket) do
    case CRM.get(socket.assigns.current_scope, id) do
      {:ok, _} ->
        {:noreply,
         push_navigate(socket, to: ~p"/admin/contacts/#{id}?locale=#{socket.assigns.locale}")}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  def handle_event("search", params, socket) do
    values = %{
      locale: socket.assigns.locale,
      q: params["search"] || socket.assigns.search,
      region: params["region"] || socket.assigns.directory_page.region,
      per: params["per"] || socket.assigns.directory_page.per,
      page: 1
    }

    values =
      Map.merge(
        values,
        PauseAiCa.CRM.Geography.filter_params(PauseAiCa.CRM.Geography.filters(params))
      )

    values = if socket.assigns.archived, do: Map.put(values, :archived, "true"), else: values

    values =
      if id = socket.assigns.directory_params["saved_filter_id"],
        do: Map.put(values, :saved_filter_id, id),
        else: values

    {:noreply, push_patch(socket, to: ~p"/admin/contacts?#{values}")}
  end

  def handle_event("select-contact", %{"id" => id}, socket) do
    if Volunteers.superadmin?(socket.assigns.current_scope) do
      selection =
        Selection.toggle(
          socket.assigns.selection,
          id,
          Enum.map(socket.assigns.records, & &1.person.id)
        )

      {:noreply, assign(socket, selection: selection, invitation_ids: [])}
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_event("select-page", _, socket) do
    if Volunteers.superadmin?(socket.assigns.current_scope) do
      selection =
        Selection.toggle_page(
          socket.assigns.selection,
          Enum.map(socket.assigns.records, & &1.person.id)
        )

      {:noreply, assign(socket, selection: selection, invitation_ids: [])}
    else
      {:noreply, denied(socket)}
    end
  end

  def handle_event("select-all-matched", _, socket) do
    result =
      if socket.assigns.grid_enabled do
        case PauseAiCa.CRM.Grid.contacts(
               socket.assigns.current_scope,
               socket.assigns.directory_params,
               socket.assigns.grid_query
             ) do
          {:ok, page} -> {:ok, page.matched_ids}
          error -> error
        end
      else
        CRM.directory_ids(socket.assigns.current_scope, socket.assigns.directory_params)
      end

    with {:ok, ids} <- result,
         {:ok, selection} <- Selection.select_all(socket.assigns.selection, ids) do
      {:noreply, assign(socket, selection: selection, invitation_ids: [], error: nil)}
    else
      {:error, :too_many_matches} ->
        {:noreply,
         assign(socket,
           error:
             gettext("More than 5,000 records match. Narrow the filters before selecting all.")
         )}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  def handle_event("clear-selection", _, socket),
    do:
      {:noreply,
       assign(socket,
         selection: Selection.clear(socket.assigns.selection),
         invitation_ids: [],
         collection_lists: nil
       )}

  def handle_event("collection-email", _, socket) do
    case PauseAiCa.ContactLists.prepare_email(
           socket.assigns.current_scope,
           Selection.ids(socket.assigns.selection)
         ) do
      {:ok, draft} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/manage/mail/drafts/#{draft.id}?locale=#{socket.assigns.locale}"
         )}

      _ ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "The selected records could not be prepared for email. Review the selection and current permissions."
             )
         )}
    end
  end

  def handle_event("collection-add-to-list", _, socket) do
    case PauseAiCa.ContactLists.list(socket.assigns.current_scope) do
      {:ok, lists} -> {:noreply, assign(socket, collection_lists: lists)}
      _ -> {:noreply, denied(socket)}
    end
  end

  def handle_event("collection-remove-from-list", _, socket) do
    scope = socket.assigns.current_scope

    with id when is_binary(id) <- socket.assigns.directory_params["saved_filter_id"],
         {:ok, list} <- PauseAiCa.ContactLists.get(scope, id),
         {:ok, _} <-
           PauseAiCa.ContactLists.remove_members(
             scope,
             id,
             Selection.ids(socket.assigns.selection),
             list.revision
           ) do
      handle_params(socket.assigns.directory_params, socket.assigns.guided_uri, socket)
    else
      _ ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "The selected contacts could not be removed from this list. Reload and review current permissions."
             )
         )}
    end
  end

  def handle_event("collection-list-save", %{"collection" => %{"list_id" => id}}, socket) do
    with list when not is_nil(list) <-
           Enum.find(socket.assigns.collection_lists || [], &(&1.id == id)),
         {:ok, _} <-
           PauseAiCa.ContactLists.add_members(
             socket.assigns.current_scope,
             id,
             Selection.ids(socket.assigns.selection),
             list.revision
           ) do
      {:noreply, assign(socket, collection_lists: nil, error: nil)}
    else
      _ ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "The list could not be updated. Reload its current revision and review the selection."
             )
         )}
    end
  end

  def handle_event("invite-account", params, socket) do
    ids = if params["id"], do: [params["id"]], else: Selection.ids(socket.assigns.selection)

    case PauseAiCa.Newsletters.Batches.contact_recipients(socket.assigns.current_scope, ids) do
      {:ok, rows} ->
        eligible = Enum.filter(rows, &(&1.status == :available))

        if eligible == [] do
          {:noreply,
           assign(socket,
             error:
               gettext(
                 "No selected contact can be emailed. Check withdrawals, blocked addresses and preferred addresses."
               )
           )}
        else
          inviter =
            socket.assigns.current_scope.user.name || socket.assigns.current_scope.user.email

          values =
            socket.assigns.invitation_form.params
            |> Map.put_new("inviter", inviter)
            |> Map.put("language", "recorded")

          {:noreply,
           assign(socket,
             invitation_ids: ids,
             invitation_targets: rows,
             invitation_languages:
               PauseAiCa.Mail.AccountInvitation.languages(Enum.map(eligible, & &1.edition)),
             invitation_form: to_form(values, as: "invitation"),
             error: nil
           )}
        end

      _ ->
        {:noreply,
         assign(socket,
           error: gettext("Select available contacts before creating an invitation.")
         )}
    end
  end

  def handle_event("edit-invitation", %{"invitation" => attrs}, socket) do
    case PhoenixMailWorkflow.Invitations.recipients(
           socket.assigns.invitation_targets,
           attrs["language"]
         ) do
      {:ok, rows} ->
        editions = rows |> Enum.filter(&(&1.status == :available)) |> Enum.map(& &1.edition)

        {:noreply,
         assign(socket,
           invitation_form: to_form(attrs, as: "invitation"),
           invitation_languages: PauseAiCa.Mail.AccountInvitation.languages(editions)
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("cancel-invitation", _, socket),
    do: {:noreply, assign(socket, invitation_ids: [])}

  def handle_event("create-invitation-drafts", %{"invitation" => attrs}, socket) do
    case PauseAiCa.Newsletters.Drafts.create_account_invitations(
           socket.assigns.current_scope,
           socket.assigns.invitation_ids,
           attrs
         ) do
      {:ok, %{drafts: [draft]}} ->
        base = ~p"/manage/mail/drafts/#{draft.id}?locale=#{socket.assigns.locale}"

        destination =
          if attrs["eligible"] == "true" do
            case PauseAiCa.Newsletters.Batches.prepare(
                   socket.assigns.current_scope,
                   draft,
                   "contacts",
                   draft.recipient_keys,
                   true
                 ) do
              {:ok, batch} -> base <> "&batch=#{batch.id}&step=review"
              _ -> base
            end
          else
            base
          end

        {:noreply, redirect(socket, to: destination)}

      {:ok, result} ->
        {:noreply,
         assign(socket,
           invitation_drafts: result.drafts,
           invitation_excluded: result.excluded,
           invitation_ids: [],
           invitation_form: to_form(attrs, as: "invitation"),
           error: nil,
           status:
             gettext(
               "Invitation drafts created for %{count} contacts. Review each draft before sending.",
               count: result.included
             )
         )}

      {:error, :invitation_context_required} ->
        {:noreply,
         assign(socket,
           invitation_form: to_form(attrs, as: "invitation"),
           error:
             gettext(
               "Enter who the invitation is from and why you are inviting them in each required language."
             )
         )}

      _ ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "No drafts were created. Reload and check the selected contacts and their email permissions."
             )
         )}
    end
  end

  def handle_event("edit", %{"contact" => attrs}, socket),
    do: {:noreply, assign(socket, form: to_form(attrs, as: "contact"), status: nil)}

  def handle_event("create", %{"contact" => attrs}, socket) do
    case CRM.create(socket.assigns.current_scope, attrs) do
      {:ok, record} ->
        {:noreply,
         push_navigate(socket,
           to: ~p"/admin/contacts/#{record.person.id}?locale=#{socket.assigns.locale}"
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, form: to_form(attrs, as: "contact"), error: contact_error(reason))}
    end
  end

  def handle_event("archive", _, socket) do
    case CRM.archive(
           socket.assigns.current_scope,
           socket.assigns.record,
           is_nil(socket.assigns.record.person.archived_at)
         ) do
      {:ok, record} -> {:noreply, load_record(socket, record)}
      {:error, reason} -> {:noreply, assign(socket, error: contact_error(reason))}
    end
  end

  def handle_event("save", %{"contact" => attrs}, socket) do
    case CRM.update(socket.assigns.current_scope, socket.assigns.record, attrs) do
      {:ok, record} ->
        {:noreply, socket |> load_record(record) |> assign(status: gettext("Saved"))}

      {:error, reason} ->
        {:noreply, assign(socket, error: contact_error(reason))}
    end
  end

  def handle_event("add-note", %{"note" => attrs}, socket) do
    case CRM.add_note(socket.assigns.current_scope, socket.assigns.record, attrs["text"]) do
      {:ok, record} ->
        form = socket.assigns.form

        {:noreply,
         socket |> load_record(record) |> assign(form: form, status: gettext("Note added"))}

      {:error, :invalid_note} ->
        {:noreply,
         assign(socket,
           note_form: to_form(attrs, as: "note"),
           note_error: gettext("Enter a note of 1 to 10,000 characters.")
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket, note_form: to_form(attrs, as: "note"), note_error: contact_error(reason))}
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

  defp geography_label(geography) do
    values =
      [
        geography.city,
        province_label(geography.subdivision),
        geography.postal_area
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    values = if values == [], do: geography.regions, else: values
    if values == [], do: gettext("Location not provided"), else: Enum.join(values, " · ")
  end

  defp directory_uri(locale, search, directory, page) do
    values = %{
      locale: locale,
      q: search,
      region: directory.region,
      per: directory.per,
      page: page
    }

    values = Map.merge(values, PauseAiCa.CRM.Geography.filter_params(directory.geography_filters))

    values =
      if Map.get(directory, :archived), do: Map.put(values, :archived, "true"), else: values

    values =
      if id = Map.get(directory, :saved_filter_id),
        do: Map.put(values, :saved_filter_id, id),
        else: values

    ~p"/admin/contacts?#{values}"
  end

  defp contact_error(%Ecto.Changeset{} = cs) do
    if Keyword.has_key?(cs.errors, :email),
      do: gettext("Enter a valid email address that is not already assigned to another contact."),
      else:
        gettext("Check the contact fields. Name and city must each be at most 200 characters.")
  end

  defp contact_error(:address_taken),
    do: gettext("This email address already belongs to another contact.")

  defp contact_error(_),
    do: gettext("Contact changed or access was revoked. Reload before saving.")

  defp load_record(socket, record) do
    scope = socket.assigns.current_scope
    {:ok, email_history} = PauseAiCa.Newsletters.Results.contact_history(scope, record.person.id)
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
      email_history: email_history,
      note_form: to_form(%{}, as: "note"),
      note_error: nil,
      note_authors: note_authors(activities),
      merges: CRM.merges(scope, record.person.id),
      form:
        to_form(
          %{
            "name" => record.person.name || "",
            "city" => record.person.city || "",
            "email" =>
              (Enum.find(record.addresses, &(&1.id == record.person.preferred_address_id)) || %{})
              |> Map.get(:email, "")
          },
          as: "contact"
        ),
      error: nil
    )
  end

  defp note_authors(activities) do
    ids =
      for %{action: "note_added", actor_id: id} <- activities,
          {:ok, id} <- [Ecto.UUID.cast(id)],
          do: id

    import Ecto.Query

    PauseAiCa.Repo.all(
      from u in PauseAiCa.Accounts.User, where: u.id in ^ids, select: {u.id, u.email}
    )
    |> Map.new()
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
      <main
        class="mx-auto max-w-6xl px-5 py-8 crm-surface"
        data-breadcrumb-label={
          cond do
            @creating -> gettext("New contact")
            @record -> @record.person.name || gettext("Contact")
            true -> gettext("Contacts")
          end
        }
      >
        <div class="management-controls mb-6 flex flex-wrap items-center justify-between gap-3">
          <h1 class="text-3xl font-bold">{gettext("Contacts")}</h1>
          <.link
            id="crm-new-contact"
            navigate={~p"/admin/contacts?locale=#{@locale}&new=true"}
            class="crm-button"
          >{gettext("New contact")}</.link>
          <.link
            navigate={~p"/admin/contacts?locale=#{@locale}&archived=#{!@archived}"}
            class="underline"
          >{if @archived, do: gettext("Active contacts"), else: gettext("Archived contacts")}</.link>
          <.link
            id="crm-import-contacts"
            navigate={~p"/admin/contact-imports?locale=#{@locale}"}
            class="crm-button"
          >{gettext("Import Contacts")}</.link>
        </div>
        <p :if={@error} id="crm-error" role="alert" class="crm-error">{@error}</p>
        <p :if={@status} role="status">{@status}</p>
        <section
          :if={@invitation_ids != []}
          id="crm-invitation"
          class="my-5 rounded-lg border border-stone-300 p-4"
        >
          <h2 class="text-xl font-bold">{gettext("Invite to create an account")}</h2>
          <p>
            {gettext(
              "For %{count} selected contacts. This creates email drafts for review; it does not send email or create accounts.",
              count: length(@invitation_ids)
            )}
          </p>
          <details class="my-3">
            <summary>{gettext("Selected recipients")}</summary>
            <ul class="max-h-64 overflow-auto">
              <li :for={target <- @invitation_targets}>
                {target.name} · {target.email || gettext("No preferred email address")}
              </li>
            </ul>
          </details>
          <.form
            for={@invitation_form}
            id="crm-invitation-form"
            phx-change="edit-invitation"
            phx-submit="create-invitation-drafts"
            class="mt-4 space-y-4"
          >
            <.input
              field={@invitation_form[:language]}
              type="select"
              label={gettext("Invitation language")}
              options={[
                {gettext("Use recorded languages · bilingual if unknown"), "recorded"},
                {gettext("English · record this language for selected contacts"), "en"},
                {gettext("French · record this language for selected contacts"), "fr"}
              ]}
            />
            <.input
              field={@invitation_form[:inviter]}
              label={gettext("Invitation from")}
              required
              maxlength="200"
            />
            <.input
              :if={"en" in @invitation_languages}
              field={@invitation_form[:reason_en]}
              type="textarea"
              label={gettext("Why you are inviting them · English")}
              required
              maxlength="3000"
            />
            <.input
              :if={"fr" in @invitation_languages}
              field={@invitation_form[:reason_fr]}
              type="textarea"
              label={gettext("Why you are inviting them · French")}
              required
              maxlength="3000"
            />
            <p>
              {gettext(
                "Recorded language determines the edition. Unknown language receives both versions. You can edit the resulting drafts before sending."
              )}
            </p>
            <label class="flex gap-3">
              <input
                type="checkbox"
                name="invitation[eligible]"
                value="true"
                checked={@invitation_form[:eligible].value == "true"}
                required
              />
              <span>{gettext("I reviewed these contacts’ eligibility for this invitation or message.")}</span>
            </label>
            <button class="crm-button" phx-disable-with={gettext("Creating drafts…")}>{gettext(
              "Review invitation"
            )}</button>
            <button type="button" phx-click="cancel-invitation" class="underline">{gettext("Cancel")}</button>
          </.form>
        </section>
        <section :if={@invitation_drafts != []} id="crm-invitation-drafts" class="my-5">
          <h2 class="text-xl font-bold">{gettext("Review invitation drafts")}</h2>
          <ul>
            <li :for={draft <- @invitation_drafts}>
              <.link
                href={~p"/manage/mail/drafts/#{draft.id}?locale=#{@locale}"}
                class="underline"
              >{draft.subject}</.link>
              · {gettext("%{count} recipients", count: length(draft.recipient_keys))}
            </li>
          </ul>
          <p :if={@invitation_excluded != []}>
            {gettext(
              "%{count} contacts excluded because an address or contact permission needs attention.",
              count: length(@invitation_excluded)
            )}
          </p>
          <ul :if={@invitation_excluded != []} class="my-3">
            <li :for={target <- @invitation_excluded}>
              {target.name} · {target.email || gettext("No preferred email address")}
            </li>
          </ul>
        </section>
        <section :if={@creating} id="crm-create" class="mb-6 max-w-xl">
          <h2 class="text-xl font-bold">{gettext("New contact")}</h2>
          <.form
            for={@form}
            id="crm-create-form"
            phx-change="edit"
            phx-submit="create"
            class="space-y-3"
          >
            <.input field={@form[:name]} label={gettext("Name")} maxlength="200" />
            <.input field={@form[:email]} label={gettext("Email")} type="email" required />
            <.input field={@form[:city]} label={gettext("City")} maxlength="200" />
            <p>
              {gettext(
                "Creating a contact does not create an account or subscribe them to a newsletter."
              )}
            </p>
            <button class="crm-button" phx-disable-with={gettext("Saving…")}>{gettext(
              "Create contact"
            )}</button>
            <.link navigate={~p"/admin/contacts?locale=#{@locale}"} class="underline">{gettext(
              "Cancel"
            )}</.link>
          </.form>
        </section>
        <section :if={is_nil(@record) and !@creating} id="crm-directory">
          <.form
            id="crm-search-form"
            for={
              to_form(%{
                "search" => @search,
                "region" => @directory_page.region,
                "per" => @directory_page.per
              })
            }
            class="management-controls grid gap-3 sm:grid-cols-[2fr_1fr_1fr]"
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
            <%= if @grid_enabled do %>
              <details id="crm-geography-options" open={@grid_geography_open} class="sm:col-span-3">
                <summary>{gettext("Geography and saved areas")}</summary>
                <div class="mt-3 grid gap-3 sm:grid-cols-2">
                  <.input
                    type="select"
                    id="crm-region"
                    name="region"
                    value={@directory_page.region}
                    label={gettext("Recorded region")}
                    options={[
                      {gettext("All regions"), ""} | Enum.map(@directory_page.regions, &{&1, &1})
                    ]}
                  />
                  <.input
                    type="select"
                    id="crm-per"
                    name="per"
                    value={@directory_page.per}
                    label={gettext("Rows per page")}
                    options={Enum.map([10, 25, 50, 100], &{to_string(&1), &1})}
                  />
                  <PauseAiCaWeb.GeographyFilterComponents.geography_filters
                    id="crm"
                    class="sm:col-span-3"
                    filters={@directory_page.geography_filters}
                    cities={@directory_page.cities}
                  />
                </div>
              </details>
            <% else %>
              <.input
                type="select"
                id="crm-region"
                name="region"
                value={@directory_page.region}
                label={gettext("Recorded region")}
                options={[{gettext("All regions"), ""} | Enum.map(@directory_page.regions, &{&1, &1})]}
              />
              <.input
                type="select"
                id="crm-per"
                name="per"
                value={@directory_page.per}
                label={gettext("Rows per page")}
                options={Enum.map([10, 25, 50, 100], &{to_string(&1), &1})}
              />
              <PauseAiCaWeb.GeographyFilterComponents.geography_filters
                id="crm"
                class="sm:col-span-3"
                filters={@directory_page.geography_filters}
                cities={@directory_page.cities}
              />
            <% end %>
          </.form>
          <p>
            {gettext(
              "Historical contacts are private. Importing or reconciling them does not create an account or consent."
            )}
          </p>
          <%= if @grid_enabled do %>
            <p id="crm-grid-count" role="status">
              {gettext("%{count} matching contacts", count: @grid_total)}
            </p>
            <button type="button" phx-click="select-all-matched" class="underline">{gettext(
              "Select all matched"
            )}</button>
            <div id="crm-selection-actions" class="my-4 flex flex-wrap items-center gap-3">
              <p role="status">
                {gettext("%{count} selected across pages", count: Selection.count(@selection))} · {gettext(
                  "%{count} selected outside the current filters",
                  count: Selection.off_filter_count(@selection, @grid_matched_ids)
                )}
              </p>
              <button
                :if={Selection.count(@selection) > 0}
                type="button"
                phx-click="clear-selection"
                class="underline"
              >{gettext("Clear selection")}</button>

              <div :if={Selection.count(@selection) > 0} class="flex flex-wrap items-center gap-3">
                <button
                  type="button"
                  phx-click="grid-open-selected"
                  disabled={Selection.count(@selection) != 1}
                  class="crm-button"
                >{gettext("Open details")}</button>
                <button
                  type="button"
                  id="crm-invite-selected"
                  phx-click="invite-account"
                  disabled={Selection.count(@selection) == 0}
                  class="crm-button"
                >{gettext("Invite selected to create an account")}</button>
                <button
                  type="button"
                  id="crm-email-selected"
                  phx-click="collection-email"
                  disabled={Selection.count(@selection) == 0}
                  class="crm-button"
                >{gettext("Email")}</button>
                <button
                  type="button"
                  id="crm-list-selected"
                  phx-click="collection-add-to-list"
                  disabled={Selection.count(@selection) == 0}
                  class="crm-button"
                >{gettext("Add to list")}</button>
                <button
                  :if={@directory_params["saved_filter_id"]}
                  type="button"
                  id="crm-remove-from-list"
                  phx-click="collection-remove-from-list"
                  disabled={Selection.count(@selection) == 0}
                  class="crm-button"
                >{gettext("Remove from list")}</button>
              </div>
              <button
                type="button"
                phx-click={JS.dispatch("data-grid:copy-range", to: "#crm-grid")}
                class="crm-button"
              >{gettext("Copy selected cells")}</button>
            </div>
            <p class="text-sm">
              {gettext("FSA = the first three characters of a Canadian postal code, for example H2X.")}
            </p>
            <p class="text-sm">{gettext("Double-click a row to open its details.")}</p>
            <PhoenixDataGrid.data_grid
              id="crm-grid"
              columns={PauseAiCaWeb.DataGridComponents.contact_columns()}
              labels={PauseAiCaWeb.DataGridComponents.labels()}
              selection={Selection.ids(@selection)}
              revision={to_string(@grid_revision)}
              options={
                %{
                  remote: true,
                  page_size: @directory_page.per,
                  storage_key: PauseAiCaWeb.DataGridComponents.storage_key(@current_scope, "contacts")
                }
              }
            />
          <% else %>
            <PhoenixAppShell.Collection.collection
              id="crm-collection"
              rows={@records}
              row_id={& &1.person.id}
              row_dom_id={&("crm-contact-" <> &1.person.id)}
              row_checkbox_id={&("crm-select-" <> &1.person.id)}
              selection={@selection}
              labels={collection_labels(@selection, @directory_page.matched_ids)}
              toggle_event="select-contact"
              page_event="select-page"
              all_event="select-all-matched"
              clear_event="clear-selection"
              selection_dom_id="crm-selection-actions"
              toolbar_class="my-4 flex flex-wrap items-center gap-4"
              scroll_class="overflow-x-auto"
              table_class="w-full text-left"
              checkbox_class="mr-2"
              button_class="underline"
            >
              <:bulk_action :let={selection}>
                <button
                  type="button"
                  id="crm-invite-selected"
                  phx-click="invite-account"
                  disabled={selection.count == 0}
                  class="crm-button"
                >{gettext("Invite selected to create an account")}</button>
                <button
                  type="button"
                  id="crm-email-selected"
                  phx-click="collection-email"
                  disabled={selection.count == 0}
                  class="crm-button"
                >{gettext("Email")}</button>
                <button
                  type="button"
                  id="crm-list-selected"
                  phx-click="collection-add-to-list"
                  disabled={selection.count == 0}
                  class="crm-button"
                >{gettext("Add to list")}</button>
                <button
                  :if={@directory_params["saved_filter_id"]}
                  type="button"
                  id="crm-remove-from-list"
                  phx-click="collection-remove-from-list"
                  disabled={selection.count == 0}
                  class="crm-button"
                >{gettext("Remove from list")}</button>
              </:bulk_action>
              <:column :let={record} label={gettext("Name")} class="p-3 align-top border-b">
                <.link
                  navigate={~p"/admin/contacts/#{record.person.id}?locale=#{@locale}"}
                  class="font-bold underline"
                >{record.person.name || gettext("Contact")}</.link>
              </:column>
              <:column :let={record} label={gettext("Email")} class="p-3 align-top border-b">
                <p :for={address <- record.addresses}>{address.email}</p>
              </:column>
              <:column
                :let={record}
                label={gettext("Current location")}
                class="p-3 align-top border-b"
              >
                <p
                  id={"crm-geography-" <> record.person.id}
                  data-geography-version={record.geography.version}
                >
                  {geography_label(record.geography)}
                  <span :if={record.geography.conflicting?}> · {gettext(
                    "Conflicting source locations"
                  )}</span>
                  <span :if={record.geography.unresolved?}> · {gettext(
                    "Some location details are unresolved"
                  )}</span>
                </p>
              </:column>
              <:column :let={record} label={gettext("Source records")} class="p-3 align-top border-b">
                <div :for={origin <- Map.get(@directory_origins, record.person.id, [])} class="mt-2">
                  <p
                    :if={length(Map.get(@directory_origins, record.person.id, [])) > 1}
                    class="text-sm font-medium text-stone-700"
                  >
                    {origin.email}
                  </p>
                  <PauseAiCaWeb.ContactSourceComponents.source_matches
                    data={origin.source_data}
                    query={@search}
                  />
                  <PauseAiCaWeb.ContactSourceComponents.source_summary
                    id={"directory-source-summary-#{origin.id}"}
                    data={origin.source_data}
                  />
                  <PauseAiCaWeb.ContactSourceComponents.source_details
                    id={"directory-source-details-#{origin.id}"}
                    data={origin.source_data}
                    query={@search}
                  />
                </div>
              </:column>
              <:empty>{gettext("No contacts found.")}</:empty>
            </PhoenixAppShell.Collection.collection>
          <% end %>
          <.form
            :if={@collection_lists != nil}
            for={to_form(%{}, as: "collection")}
            id="crm-add-to-list"
            phx-submit="collection-list-save"
            class="management-controls"
          >
            <.input
              name="collection[list_id]"
              value=""
              type="select"
              label={gettext("List")}
              prompt={gettext("Choose a list")}
              options={Enum.map(@collection_lists, &{&1.name, &1.id})}
            />
            <button class="crm-button" disabled={Selection.count(@selection) == 0}>{gettext(
              "Add selected to list"
            )}</button>
          </.form>
          <nav
            :if={!@grid_enabled}
            id="crm-pagination"
            aria-label={gettext("Contact pages")}
            class="mt-4 flex flex-wrap items-center gap-4"
          >
            <p role="status">
              {gettext("Page %{page} of %{pages} · %{total} contacts",
                page: @directory_page.page,
                pages: @directory_page.pages,
                total: @directory_page.total
              )}
            </p>
            <.link
              :if={@directory_page.page > 1}
              patch={directory_uri(@locale, @search, @directory_page, @directory_page.page - 1)}
              class="underline"
            >{gettext("Previous")}</.link>
            <span :if={@directory_page.page == 1} aria-disabled="true" class="text-stone-500">{gettext(
              "Previous"
            )}</span>
            <.link
              :if={@directory_page.page < @directory_page.pages}
              patch={directory_uri(@locale, @search, @directory_page, @directory_page.page + 1)}
              class="underline"
            >{gettext("Next")}</.link>
            <span
              :if={@directory_page.page == @directory_page.pages}
              aria-disabled="true"
              class="text-stone-500"
            >{gettext("Next")}</span>
          </nav>
        </section>
        <section :if={@record} id="crm-record">
          <.link navigate={~p"/admin/contacts?locale=#{@locale}"} class="underline">{gettext(
            "Back to contacts"
          )}</.link>
          <p :if={@record.person.archived_at} role="status">{gettext("Archived contact")}</p>
          <button
            id="crm-archive-contact"
            type="button"
            phx-click="archive"
            data-confirm={
              if is_nil(@record.person.archived_at),
                do:
                  gettext(
                    "Archive this contact? Contact-based sends will exclude them. History and newsletter subscription choices are retained."
                  ),
                else: gettext("Restore this contact to the active directory?")
            }
            class="ml-4 underline"
          >{if is_nil(@record.person.archived_at),
            do: gettext("Archive contact"),
            else: gettext("Restore contact")}</button>

          <button
            :if={@record.addresses != []}
            type="button"
            phx-click="invite-account"
            phx-value-id={@record.person.id}
            class="crm-button mb-5"
          >{gettext("Invite to create an account")}</button>
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
            <.input field={@form[:email]} label={gettext("Preferred email")} type="email" required />
            <p>
              {gettext(
                "Changing the preferred email retains previous addresses and their history. Subscription permissions do not transfer to the new address."
              )}
            </p>
            <button class="crm-button" phx-disable-with={gettext("Saving…")}>{gettext("Save contact")}</button>
          </.form>
          <section id="crm-notes" class="mt-8 space-y-4">
            <h2 class="text-xl font-bold">{gettext("Private contact notes")}</h2>
            <.form for={@note_form} id="crm-note-form" phx-submit="add-note" class="space-y-3">
              <.input
                field={@note_form[:text]}
                type="textarea"
                label={gettext("New note")}
                required
                maxlength="10000"
              />
              <p :if={@note_error} id="crm-note-error" role="alert">{@note_error}</p>
              <button class="crm-button" phx-disable-with={gettext("Saving…")}>{gettext("Add note")}</button>
            </.form>
            <article
              :for={note <- Enum.filter(@activities, &(&1.action == "note_added"))}
              class="rounded-lg border border-stone-200 p-4"
            >
              <p class="text-sm">
                {Map.get(@note_authors, note.actor_id, gettext("Not recorded"))} ·
                <time datetime={DateTime.to_iso8601(note.inserted_at)}>{Calendar.strftime(
                  note.inserted_at,
                  "%Y-%m-%d %H:%M UTC"
                )}</time>
              </p>
              <p class="whitespace-pre-wrap break-words">{note.details["text"]}</p>
            </article>
          </section>
          <section id="crm-addresses" class="mt-8">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="text-xl font-bold">{gettext("Addresses")}</h2>
              <.link
                id="crm-email-preferences"
                href={~p"/manage/mail/preferences?locale=#{@locale}&contact_id=#{@record.person.id}"}
                class="underline"
              >{gettext("Email preferences")}</.link>
            </div><ul>
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
              <PauseAiCaWeb.ContactSourceComponents.source_details
                id={"profile-source-details-#{origin.id}"}
                data={origin.source_data}
                query={@search}
              />
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
          <section id="crm-email-history" class="mt-8">
            <h2 class="text-xl font-bold">{gettext("Email history")}</h2>
            <p>{gettext("Latest 100 recorded send attempts across this contact’s addresses.")}</p>
            <p :if={@email_history == []}>{gettext("No recorded sends.")}</p>
            <article :for={entry <- @email_history} class="border-b py-3">
              <.link
                :if={entry.delivery.batch_id}
                href={~p"/manage/mail/results/#{entry.delivery.batch_id}?locale=#{@locale}"}
                class="font-bold underline"
              >{entry.subject}</.link>
              <strong :if={is_nil(entry.delivery.batch_id)}>{entry.subject}</strong>
              <p>
                {gettext("Sent by")}: {entry.admin_name} {entry.admin_email || gettext("Not recorded")}
              </p>
              <p>{gettext("From address")}: {entry.sender_name} &lt;{entry.sender_email}&gt;</p>
              <p>
                {entry.delivery.email} · {entry.delivery.state} ·
                <time datetime={DateTime.to_iso8601(entry.delivery.attempted_at)}>{Calendar.strftime(
                  entry.delivery.attempted_at,
                  "%Y-%m-%d %H:%M UTC"
                )}</time>
              </p>
            </article>
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

  defp collection_labels(selection, matched_ids) do
    %{
      selection: gettext("%{count} selected across pages", count: Selection.count(selection)),
      off_filter:
        gettext("%{count} selected outside the current filters",
          count: Selection.off_filter_count(selection, matched_ids)
        ),
      select_all: gettext("Select all matched"),
      select_page: gettext("Select this page"),
      clear: gettext("Clear selection"),
      select_row: fn record ->
        gettext("Select %{name}", name: record.person.name || gettext("contact"))
      end
    }
  end
end
