defmodule PauseAiCaWeb.ContactListsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{ContactLists, Volunteers}
  alias PhoenixAppShell.Selection

  def mount(params, session, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.superadmin?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Lists"),
         lists: [],
         grid_enabled: PauseAiCaWeb.DataGridComponents.enabled?(),
         grid_revision: 0,
         grid_matched_ids: [],
         grid_query: %{},
         selection: Selection.new(),
         selected_list: nil,
         editing_list: nil,
         list_form: to_form(ContactLists.form(nil), as: "list"),
         members: nil,
         archived?: false,
         kind: "all",
         query: "",
         error: nil,
         guide_token: nil,
         guided_login: PauseAiCa.Assistant.GuidedMode.session_fingerprint(session["user_token"]),
         current_uri: nil
       )}
    else
      {:ok, denied(socket)}
    end
  end

  def handle_params(params, uri, socket) do
    archived? = params["archived"] == "true"

    with {:ok, lists} <- ContactLists.list(socket.assigns.current_scope, archived?),
         {:ok, selected} <- selected_list(socket.assigns.current_scope, params["list_id"]) do
      query = String.slice(params["q"] || "", 0, 200)
      kind = if params["kind"] in ["static", "dynamic"], do: params["kind"], else: "all"

      rows =
        Enum.filter(lists, fn list ->
          (kind == "all" or list_kind(list) == kind) and
            String.contains?(String.downcase(list.name), String.downcase(query))
        end)

      socket =
        socket
        |> assign(
          lists: rows,
          grid_revision: socket.assigns.grid_revision + 1,
          selected_list: selected,
          members: member_page(socket.assigns.current_scope, selected),
          query: query,
          kind: kind,
          archived?: archived?,
          current_uri: uri
        )
        |> reset_editor(selected)

      observe(socket)
      {:noreply, socket}
    else
      _ -> {:noreply, denied(socket)}
    end
  end

  def handle_event(
        "data_grid:query",
        %{"id" => "lists-grid", "request_id" => request_id} = payload,
        socket
      )
      when is_binary(request_id) and byte_size(request_id) <= 200 do
    if match?(
         {:ok, _},
         PhoenixDataGrid.Query.normalize(payload, PauseAiCaWeb.DataGridComponents.list_columns())
       ) do
      original_payload = payload
      payload = grid_payload(socket, payload)

      case PauseAiCa.CRM.Grid.lists(
             socket.assigns.current_scope,
             socket.assigns.archived?,
             payload
           ) do
        {:ok, page} ->
          {:noreply,
           socket
           |> assign(grid_matched_ids: page.matched_ids, grid_query: original_payload)
           |> push_event(
             "data_grid:rows",
             PauseAiCa.CRM.Grid.reply(page, "lists-grid", request_id)
           )}

        {:error, :unauthorized} ->
          {:noreply, denied(socket)}

        _ ->
          {:noreply,
           push_event(socket, "data_grid:rows", %{
             id: "lists-grid",
             request_id: request_id,
             error: true
           })}
      end
    else
      {:noreply,
       push_event(socket, "data_grid:rows", %{
         id: "lists-grid",
         request_id: request_id,
         error: true
       })}
    end
  end

  def handle_event("data_grid:selection", %{"id" => "lists-grid", "ids" => ids}, socket)
      when is_list(ids) and length(ids) <= 5000 do
    with {:ok, lists} <- ContactLists.list(socket.assigns.current_scope, socket.assigns.archived?),
         true <- Enum.all?(ids, &(&1 in Enum.map(lists, fn list -> list.id end))),
         {:ok, selection} <- Selection.select_all(Selection.new(), ids) do
      {:noreply, assign(socket, selection: selection)}
    else
      _ -> {:noreply, denied(socket)}
    end
  end

  def handle_event("data_grid:open_row", %{"id" => "lists-grid", "row_id" => id}, socket) do
    case ContactLists.get(socket.assigns.current_scope, id) do
      {:ok, _} ->
        {:noreply,
         push_patch(socket, to: ~p"/manage/lists?locale=#{socket.assigns.locale}&list_id=#{id}")}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  def handle_event("filter", %{"filters" => filters}, socket) do
    {:noreply,
     push_patch(socket,
       to:
         ~p"/manage/lists?#{Map.merge(filters, %{"locale" => socket.assigns.locale, "archived" => to_string(socket.assigns.archived?)})}"
     )}
  end

  def handle_event("select-list", %{"id" => id}, socket) do
    {:noreply,
     assign(socket,
       selection: Selection.toggle(socket.assigns.selection, id, visible_ids(socket))
     )}
  end

  def handle_event("select-page", _, socket),
    do:
      {:noreply,
       assign(socket,
         selection: Selection.toggle_page(socket.assigns.selection, visible_ids(socket))
       )}

  def handle_event("select-all", _, socket) do
    result =
      if socket.assigns.grid_enabled do
        case PauseAiCa.CRM.Grid.lists(
               socket.assigns.current_scope,
               socket.assigns.archived?,
               grid_payload(socket, socket.assigns.grid_query)
             ) do
          {:ok, page} -> {:ok, page.matched_ids}
          error -> error
        end
      else
        {:ok, visible_ids(socket)}
      end

    with {:ok, ids} <- result,
         {:ok, selection} <- Selection.select_all(socket.assigns.selection, ids) do
      {:noreply, assign(socket, selection: selection)}
    else
      _ -> {:noreply, assign(socket, error: gettext("Narrow the filters before selecting all."))}
    end
  end

  def handle_event("clear", _, socket),
    do: {:noreply, assign(socket, selection: Selection.clear(socket.assigns.selection))}

  def handle_event("new", _, socket) do
    {:noreply,
     socket
     |> assign(
       editing_list: nil,
       list_form: to_form(ContactLists.form(nil), as: "list"),
       error: nil
     )
     |> push_patch(to: ~p"/manage/lists?locale=#{socket.assigns.locale}")}
  end

  def handle_event("edit-selected", _, socket) do
    case Selection.ids(socket.assigns.selection) do
      [id] ->
        {:noreply,
         push_patch(socket, to: ~p"/manage/lists?locale=#{socket.assigns.locale}&list_id=#{id}")}

      _ ->
        {:noreply, assign(socket, error: gettext("Select one list to edit."))}
    end
  end

  def handle_event("list-change", %{"list" => attrs}, socket),
    do: {:noreply, assign(socket, list_form: to_form(attrs, as: "list"))}

  def handle_event("list-save", %{"list" => attrs}, socket) do
    case ContactLists.save(socket.assigns.current_scope, socket.assigns.editing_list, attrs) do
      {:ok, list} ->
        {:noreply,
         socket
         |> assign(
           editing_list: list,
           list_form: to_form(ContactLists.form(list), as: "list"),
           error: nil
         )
         |> push_patch(to: ~p"/manage/lists?locale=#{socket.assigns.locale}&list_id=#{list.id}")}

      {:error, :unauthorized} ->
        {:noreply, denied(socket)}

      {:error, :stale} ->
        {:noreply, assign(socket, error: gettext("This list changed. Reopen it before editing."))}

      _ ->
        {:noreply,
         assign(socket,
           list_form: to_form(attrs, as: "list"),
           error:
             gettext("Enter a unique name and valid list rules. Your entries have been kept.")
         )}
    end
  end

  def handle_event("archive-selected", _, socket), do: change_archive(socket, :archive)
  def handle_event("restore-selected", _, socket), do: change_archive(socket, :restore)

  def handle_event("compose-newsletter", _, socket) do
    with %{id: id} <- socket.assigns.selected_list,
         {:ok, draft} <-
           PauseAiCa.Newsletters.Drafts.create_for_list(socket.assigns.current_scope, id) do
      if socket.assigns.guide_token do
        PauseAiCa.Assistant.GuidedMode.observe_list(
          socket.assigns.current_scope,
          socket.assigns.guide_token,
          socket.assigns.current_uri,
          socket.assigns.guided_login,
          id,
          draft.id
        )
      end

      {:noreply,
       push_navigate(socket,
         to:
           ~p"/manage/mail/drafts/#{draft.id}?locale=#{socket.assigns.locale}&workspace=newsletters"
       )}
    else
      _ ->
        {:noreply,
         assign(socket, error: gettext("This list could not be prepared for a newsletter."))}
    end
  end

  def handle_event("compose-email", _, socket) do
    with %{id: id} <- socket.assigns.selected_list,
         {:ok, ids} <-
           PauseAiCa.CRM.directory_ids(socket.assigns.current_scope, %{"saved_filter_id" => id}),
         {:ok, draft} <- ContactLists.prepare_email(socket.assigns.current_scope, ids) do
      {:noreply,
       push_navigate(socket,
         to: ~p"/manage/mail/drafts/#{draft.id}?locale=#{socket.assigns.locale}&workspace=emails"
       )}
    else
      _ ->
        {:noreply,
         assign(socket,
           error:
             gettext("This list could not be prepared for email. Check its current contacts.")
         )}
    end
  end

  def handle_event("assistant-guided-observe", %{"token" => token}, socket) do
    socket = assign(socket, guide_token: token)
    observe(socket)
    {:noreply, socket}
  end

  defp grid_payload(socket, payload) do
    Map.update(payload, "filters", [], fn filters ->
      filters ++
        if(socket.assigns.query == "",
          do: [],
          else: [
            %{"field" => "name", "operator" => "contains", "value" => socket.assigns.query}
          ]
        ) ++
        if socket.assigns.kind == "all",
          do: [],
          else: [%{"field" => "kind", "operator" => "eq", "value" => socket.assigns.kind}]
    end)
  end

  defp observe(%{assigns: %{guide_token: nil}}), do: :ok

  defp observe(socket) do
    PauseAiCa.Assistant.GuidedMode.observe_list(
      socket.assigns.current_scope,
      socket.assigns.guide_token,
      socket.assigns.current_uri,
      socket.assigns.guided_login,
      socket.assigns.selected_list && socket.assigns.selected_list.id
    )
  end

  defp selected_list(_, id) when id in [nil, ""], do: {:ok, nil}
  defp selected_list(scope, id), do: ContactLists.get(scope, id)
  defp member_page(_, nil), do: nil

  defp member_page(scope, list) do
    case PauseAiCa.CRM.directory_page(scope, %{"saved_filter_id" => list.id}) do
      {:ok, page} -> page
      _ -> nil
    end
  end

  defp reset_editor(socket, list) do
    current = socket.assigns.editing_list

    if (current && current.id) == (list && list.id),
      do: socket,
      else:
        assign(socket,
          editing_list: list,
          list_form: to_form(ContactLists.form(list), as: "list"),
          error: nil
        )
  end

  defp change_archive(socket, action) do
    scope = socket.assigns.current_scope

    result =
      Enum.reduce_while(Selection.ids(socket.assigns.selection), :ok, fn id, _ ->
        with {:ok, list} <- ContactLists.get(scope, id),
             true <-
               (action == :archive and is_nil(list.archived_at)) or
                 (action == :restore and not is_nil(list.archived_at)),
             {:ok, _} <- apply(ContactLists, action, [scope, list]) do
          {:cont, :ok}
        else
          _ -> {:halt, :error}
        end
      end)

    socket =
      assign(socket,
        selection: Selection.clear(socket.assigns.selection),
        error:
          if(result == :error,
            do: gettext("Some lists could not be changed. Review their current status.")
          )
      )

    {:noreply,
     push_patch(socket,
       to: ~p"/manage/lists?locale=#{socket.assigns.locale}&archived=#{socket.assigns.archived?}"
     )}
  end

  defp visible_ids(socket), do: Enum.map(socket.assigns.lists, & &1.id)
  defp list_kind(list), do: if(list.criteria["kind"] == "static", do: "static", else: "dynamic")

  defp labels(selection, rows) do
    outside = Selection.off_filter_count(selection, Enum.map(rows, & &1.id))

    %{
      selection: gettext("%{count} selected", count: Selection.count(selection)),
      off_filter:
        if(outside > 0,
          do:
            ngettext(
              "%{count} selected outside these filters",
              "%{count} selected outside these filters",
              outside
            )
        ),
      select_page: gettext("Select this page"),
      select_all: gettext("Select all matching"),
      clear: gettext("Clear selection"),
      select_row: & &1.name
    }
  end

  defp denied(socket),
    do:
      socket
      |> put_flash(:error, gettext("Superadmin access required."))
      |> redirect(to: ~p"/dashboard")

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="contact_lists"
    >
      <section id="contact-lists" class="space-y-6">
        <div id="assistant-guided-workspace"></div>
        <div class="management-controls space-y-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h1 class="text-2xl font-bold">{gettext("Lists")}</h1>
            <button type="button" phx-click="new" class="crm-button">{gettext("New list")}</button>
          </div>
          <nav class="flex gap-4" aria-label={gettext("List status")}>
            <.link
              patch={~p"/manage/lists?locale=#{@locale}"}
              aria-current={if !@archived?, do: "page"}
            >{gettext("All lists")}</.link>
            <.link
              patch={~p"/manage/lists?locale=#{@locale}&archived=true"}
              aria-current={if @archived?, do: "page"}
            >{gettext("Archived")}</.link>
          </nav>
          <.form
            for={to_form(%{"q" => @query, "kind" => @kind}, as: "filters")}
            id="contact-list-filters"
            phx-change="filter"
            phx-submit="filter"
            class="flex flex-wrap gap-4"
          >
            <.input
              name="filters[q]"
              value={@query}
              label={gettext("Find a list")}
              phx-debounce="300"
            />
            <.input
              name="filters[kind]"
              value={@kind}
              type="select"
              label={gettext("Type")}
              options={[
                {gettext("All types"), "all"},
                {gettext("Static"), "static"},
                {gettext("Dynamic"), "dynamic"}
              ]}
            />
          </.form>
        </div>
        <p :if={@error} role="alert" class="text-red-800">{@error}</p>
        <%= if @grid_enabled do %>
          <button type="button" phx-click="select-all" class="underline">{gettext(
            "Select all matched"
          )}</button>
          <div class="my-4 flex flex-wrap items-center gap-3">
            <p role="status">
              {gettext("%{count} selected across pages", count: Selection.count(@selection))}
            </p>
            <button type="button" phx-click="clear" class="underline">{gettext("Clear selection")}</button>

            <button
              type="button"
              phx-click="edit-selected"
              disabled={Selection.count(@selection) != 1}
              class="crm-button"
            >{gettext("Edit")}</button>
            <button
              :if={!@archived?}
              type="button"
              phx-click="archive-selected"
              disabled={Selection.count(@selection) == 0}
              class="underline"
            >{gettext("Archive")}</button>
            <button
              :if={@archived?}
              type="button"
              phx-click="restore-selected"
              disabled={Selection.count(@selection) == 0}
              class="underline"
            >{gettext("Restore")}</button>
          </div>
          <p class="text-sm">{gettext("Double-click a row to open its details.")}</p>
          <PhoenixDataGrid.data_grid
            id="lists-grid"
            columns={PauseAiCaWeb.DataGridComponents.list_columns()}
            labels={PauseAiCaWeb.DataGridComponents.labels()}
            selection={Selection.ids(@selection)}
            revision={to_string(@grid_revision)}
            options={
              %{
                remote: true,
                page_size: 25,
                storage_key: PauseAiCaWeb.DataGridComponents.storage_key(@current_scope, "lists")
              }
            }
          />
        <% else %>
          <PhoenixAppShell.Collection.collection
            id="contact-list-collection"
            rows={@lists}
            row_id={& &1.id}
            row_dom_id={&("contact-list-" <> &1.id)}
            selection={@selection}
            labels={labels(@selection, @lists)}
            toggle_event="select-list"
            page_event="select-page"
            all_event="select-all"
            clear_event="clear"
            toolbar_class="flex flex-wrap items-center gap-4 mb-4"
            scroll_class="overflow-x-auto"
            table_class="w-full text-left"
            button_class="underline"
          >
            <:bulk_action :let={selection}>
              <button
                type="button"
                phx-click="edit-selected"
                disabled={selection.count != 1}
                class="crm-button"
              >{gettext("Edit")}</button>
              <button
                :if={!@archived?}
                type="button"
                phx-click="archive-selected"
                disabled={selection.count == 0}
                class="underline"
              >{gettext("Archive")}</button>
              <button
                :if={@archived?}
                type="button"
                phx-click="restore-selected"
                disabled={selection.count == 0}
                class="underline"
              >{gettext("Restore")}</button>
            </:bulk_action>
            <:column :let={list} label={gettext("Name")} class="p-3 border-b">
              <.link
                patch={~p"/manage/lists?locale=#{@locale}&list_id=#{list.id}"}
                class="underline font-bold"
              >{list.name}</.link>
            </:column>
            <:column :let={list} label={gettext("Type")} class="p-3 border-b">
              {if list_kind(list) == "static", do: gettext("Static"), else: gettext("Dynamic")}
            </:column>
            <:column :let={list} label={gettext("Revision")} class="p-3 border-b">
              {list.revision}
            </:column>
            <:empty>{gettext("No lists match these filters.")}</:empty>
          </PhoenixAppShell.Collection.collection>
        <% end %>
        <section
          :if={@selected_list}
          id="selected-contact-list"
          data-list-id={@selected_list.id}
          data-list-revision={@selected_list.revision}
          class="management-controls space-y-3"
        >
          <h2 class="text-xl font-bold">{@selected_list.name}</h2>
          <p :if={@members}>{gettext("%{count} matching contacts", count: @members.total)}</p>
          <div class="flex flex-wrap gap-4">
            <.link
              navigate={~p"/admin/contacts?locale=#{@locale}&saved_filter_id=#{@selected_list.id}"}
              class="underline"
            >{gettext("View contacts")}</.link>
            <button
              id="contact-list-compose-email"
              type="button"
              phx-click="compose-email"
              disabled={@selected_list.archived_at != nil}
              class="crm-button"
            >{gettext("Compose email")}</button>
            <button
              id="contact-list-compose-newsletter"
              type="button"
              phx-click="compose-newsletter"
              disabled={@selected_list.archived_at != nil}
              class="crm-button"
            >{gettext("Compose newsletter")}</button>
          </div>
          <p>
            {gettext(
              "Newsletter recipients must also be subscribed and eligible for the selected edition."
            )}
          </p>
        </section>
        <.form
          for={@list_form}
          id="contact-list-form"
          phx-change="list-change"
          phx-submit="list-save"
          class="management-controls space-y-4"
        >
          <h2 class="text-xl font-bold">
            {if @editing_list, do: gettext("Edit list"), else: gettext("New list")}
          </h2>
          <.input field={@list_form[:name]} label={gettext("Name")} required />
          <.input
            field={@list_form[:kind]}
            type="select"
            label={gettext("Type")}
            options={[{gettext("Dynamic"), "dynamic"}, {gettext("Static"), "static"}]}
            disabled={@editing_list != nil}
          />
          <input :if={@editing_list} type="hidden" name="list[kind]" value={@list_form[:kind].value} />
          <div :if={@list_form[:kind].value != "static"} class="grid gap-4 md:grid-cols-3">
            <.input field={@list_form[:city]} label={gettext("Cities")} />
            <.input field={@list_form[:region]} label={gettext("Recorded regions")} />
            <.input
              field={@list_form[:fsas]}
              label={gettext("FSAs — first three postal-code characters")}
            />
          </div>
          <p :if={@list_form[:kind].value != "static"}>
            {gettext(
              "Separate values with commas. A contact matches any city, recorded region or FSA rule."
            )}
          </p>
          <p
            :if={@editing_list && PhoenixCRM.ListRules.match_mode(@editing_list.criteria) == "all"}
            role="note"
          >
            {gettext(
              "This existing list requires every rule. Saving this form changes it to match any rule."
            )}
          </p>
          <p :if={@list_form[:kind].value == "static"}>
            {gettext("Add selected people from Contacts or Accounts after saving this list.")}
          </p>
          <button
            id="contact-list-save"
            class="crm-button"
            disabled={@editing_list && @editing_list.archived_at != nil}
          >{gettext("Save list")}</button>
        </.form>
      </section>
    </Layouts.management>
    """
  end
end
