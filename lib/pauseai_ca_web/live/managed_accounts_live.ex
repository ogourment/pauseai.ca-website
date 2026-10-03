defmodule PauseAiCaWeb.ManagedAccountsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{AccountManagement, AccountEmailHistory, Volunteers}
  alias PauseAiCa.Accounts.UserNotifier
  alias PauseAiCaWeb.VolunteerForms

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Volunteers.allowed?(socket.assigns.current_scope) do
      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Accounts"),
         records: [],
         count: 0,
         pages: 1,
         confirm_role: false,
         admin?: Volunteers.superadmin?(socket.assigns.current_scope),
         groups: Volunteers.groups(socket.assigns.current_scope),
         managers: [],
         mail_filters: AccountEmailHistory.defaults(),
         mail_results: %{},
         mail_loading: false,
         mail_error: nil,
         search: "",
         page: 1,
         record: nil,
         form: to_form(%{}, as: "account"),
         errors: %{},
         batches: Volunteers.list_batches(socket.assigns.current_scope)
       )}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Organizer access required."))
       |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    if id = params["id"] do
      case AccountManagement.get(socket.assigns.current_scope, id) do
        {:ok, record} ->
          values = account_values(record)

          same? = socket.assigns.record && socket.assigns.record.user.id == id

          socket =
            if same?,
              do: socket,
              else:
                assign(socket,
                  form: to_form(values, as: "account"),
                  confirm_role: false,
                  errors: %{},
                  mail_results: %{},
                  mail_error: nil,
                  mail_loading: false
                )

          filters =
            Map.merge(
              AccountEmailHistory.defaults(),
              for(
                {key, value} <- params,
                String.starts_with?(key, "mail_"),
                into: %{},
                do: {String.replace_prefix(key, "mail_", ""), value}
              )
            )

          {:noreply,
           assign(socket,
             record: record,
             mail_filters: filters,
             admin?: Volunteers.superadmin?(socket.assigns.current_scope),
             groups: Volunteers.groups(socket.assigns.current_scope),
             managers:
               Enum.filter(Volunteers.managers(socket.assigns.current_scope), &(&1.user_id == id))
           )}

        _ ->
          {:noreply,
           socket
           |> put_flash(:error, gettext("Account unavailable."))
           |> push_navigate(to: ~p"/manage/accounts?locale=#{socket.assigns.locale}")}
      end
    else
      search = params["q"] || ""

      page =
        case Integer.parse(params["page"] || "1") do
          {n, ""} when n > 0 -> n
          _ -> 1
        end

      count = AccountManagement.count(socket.assigns.current_scope, search)
      pages = max(Integer.ceil_div(count, 25), 1)
      page = min(page, pages)

      {:noreply,
       assign(socket,
         count: count,
         pages: pages,
         record: nil,
         search: search,
         page: page,
         records: AccountManagement.list(socket.assigns.current_scope, search, page)
       )}
    end
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket),
    do:
      {:noreply,
       push_patch(socket, to: ~p"/manage/accounts?#{%{locale: socket.assigns.locale, q: search}}")}

  def handle_event("edit", %{"account" => attrs}, socket),
    do: {:noreply, assign(socket, form: to_form(attrs, as: "account"))}

  def handle_event("save", %{"account" => attrs}, socket) do
    case AccountManagement.update(
           socket.assigns.current_scope,
           socket.assigns.record.user.id,
           attrs
         ) do
      {:ok, _} ->
        case AccountManagement.get(socket.assigns.current_scope, socket.assigns.record.user.id) do
          {:ok, record} ->
            {:noreply,
             socket
             |> assign(
               record: record,
               form: to_form(account_values(record), as: "account"),
               errors: %{}
             )
             |> put_flash(:info, gettext("Account saved."))}

          _ ->
            {:noreply, redirect(socket, to: ~p"/manage/accounts")}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(
           form: to_form(attrs, as: "account"),
           errors: if(is_map(reason), do: reason, else: %{"group_id" => :unauthorized_group})
         )
         |> put_flash(:error, gettext("Changes not saved. Check the fields and your access."))}
    end
  end

  def handle_event("confirm-role", _, socket) do
    if Volunteers.superadmin?(socket.assigns.current_scope),
      do: {:noreply, assign(socket, :confirm_role, true)},
      else: {:noreply, put_flash(socket, :error, gettext("Superadmin access required."))}
  end

  def handle_event("set-superadmin", %{"enabled" => value}, socket) do
    case AccountManagement.set_superadmin(
           socket.assigns.current_scope,
           socket.assigns.record.user.id,
           value == "true"
         ) do
      {:ok, {user, changed?}} ->
        notification =
          if changed? and user.superadmin,
            do:
              UserNotifier.deliver_superadmin_granted(
                user,
                PauseAiCaWeb.Endpoint.url() <> "/manage/accounts",
                socket.assigns.current_scope.user.id
              ),
            else: {:ok, nil}

        message =
          case notification do
            {:error, _} ->
              gettext("Role granted, but the notification email could not be sent.")

            _ ->
              if user.superadmin,
                do: gettext("Superadmin role granted."),
                else: gettext("Superadmin role removed.")
          end

        socket = socket |> put_flash(:info, message) |> assign(:confirm_role, false)

        socket =
          if changed? and user.superadmin and match?({:ok, _}, notification),
            do: put_flash(socket, :dev_mailbox, true),
            else: socket

        socket =
          if socket.assigns.current_scope.user.id == user.id,
            do: assign(socket, :current_scope, PauseAiCa.Accounts.Scope.for_user(user)),
            else: socket

        case AccountManagement.get(socket.assigns.current_scope, user.id) do
          {:ok, record} ->
            {:noreply,
             assign(socket,
               record: record,
               admin?: Volunteers.superadmin?(socket.assigns.current_scope)
             )}

          _ ->
            {:noreply, redirect(socket, to: ~p"/dashboard")}
        end

      {:error, reason} ->
        message =
          case reason do
            :last_superadmin ->
              gettext("The last superadmin cannot be removed.")

            :email_unconfirmed ->
              gettext("Confirm this account's email before granting superadmin access.")

            _ ->
              gettext("Superadmin access required.")
          end

        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("assign-manager", %{"manager" => %{"group_id" => group}}, socket) do
    case Volunteers.assign_manager(
           socket.assigns.current_scope,
           group,
           socket.assigns.record.user.email
         ) do
      {:ok, _} ->
        {:noreply, reload_access(socket)}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Superadmin access and a confirmed account are required.")
         )}
    end
  end

  def handle_event("revoke-manager", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.managers, &(&1.id == id)) and
         Volunteers.revoke_manager(socket.assigns.current_scope, id) == :ok do
      {:noreply, reload_access(socket)}
    else
      {:noreply, put_flash(socket, :error, gettext("Superadmin access required."))}
    end
  end

  def handle_event("email-history", %{"history" => filters}, socket) do
    scope = socket.assigns.current_scope
    id = socket.assigns.record.user.id

    with {:ok, _} <- AccountManagement.get(scope, id),
         {:ok, range} <- AccountEmailHistory.range(filters) do
      same_range? = Map.take(filters, ["from", "to", "page"]) == socket.assigns.mail_filters

      query =
        Map.merge(
          %{"locale" => socket.assigns.locale},
          Map.new(filters, fn {k, v} -> {"mail_" <> k, v} end)
        )

      {:noreply,
       socket
       |> assign(
         mail_filters: filters,
         mail_loading: true,
         mail_error: nil,
         mail_results: if(same_range?, do: socket.assigns.mail_results, else: %{})
       )
       |> start_async(:email_history, fn -> AccountEmailHistory.load(scope, id, filters) end)
       |> assign(:mail_range, range)
       |> push_patch(to: ~p"/manage/accounts/#{id}?#{query}")}
    else
      {:error, :unauthorized} ->
        {:noreply,
         assign(socket, mail_results: %{}, mail_error: :unauthorized, mail_loading: false)}

      _ ->
        {:noreply, assign(socket, mail_error: :invalid_range, mail_loading: false)}
    end
  end

  @impl true
  def handle_async(:email_history, {:ok, {:ok, result}}, socket) do
    if socket.assigns.record && result.account_id == socket.assigns.record.user.id &&
         AccountEmailHistory.range(socket.assigns.mail_filters) == {:ok, result.filters} &&
         match?(
           {:ok, _},
           AccountManagement.get(socket.assigns.current_scope, socket.assigns.record.user.id)
         ) do
      results =
        Enum.reduce([:transactional, :campaigns], socket.assigns.mail_results, fn source, cache ->
          value =
            case result[source] do
              {:ok, data} ->
                Map.put(data, :error, nil)

              {:error, reason} ->
                Map.put(
                  Map.get(cache, source, %{
                    rows: [],
                    refreshed_at: nil,
                    more: false,
                    partial: false
                  }),
                  :error,
                  reason
                )
            end

          Map.put(cache, source, value)
        end)

      {:noreply, assign(socket, mail_results: results, mail_loading: false)}
    else
      {:noreply,
       assign(socket, mail_results: %{}, mail_error: :unauthorized, mail_loading: false)}
    end
  end

  def handle_async(:email_history, {:ok, {:error, reason}}, socket),
    do:
      {:noreply,
       assign(socket,
         mail_loading: false,
         mail_error: reason,
         mail_results: if(reason == :unauthorized, do: %{}, else: socket.assigns.mail_results)
       )}

  def handle_async(:email_history, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, mail_loading: false, mail_error: :unavailable)}

  defp account_values(record),
    do: %{
      "name" => record.user.name,
      "postal_code" => record.user.postal_code,
      "city" => record.user.city,
      "notes" => record.user.organizer_notes,
      "group_id" => record.user.organizing_group_id
    }

  defp reload_access(socket),
    do:
      assign(
        socket,
        :managers,
        Enum.filter(
          Volunteers.managers(socket.assigns.current_scope),
          &(&1.user_id == socket.assigns.record.user.id)
        )
      )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={~p"/manage/accounts?locale=#{if(@locale == "fr", do: "en", else: "fr")}"}
    >
      <section id="managed-accounts" class="mx-auto max-w-6xl space-y-6 px-5 py-12">
        <h1 class="text-4xl font-bold">{gettext("Accounts")}</h1>

        <%= if @record do %>
          <.link navigate={~p"/manage/accounts?locale=#{@locale}"} class="underline">{gettext(
            "Back to accounts"
          )}</.link>
          <h2 class="text-2xl font-bold">{@record.user.email}</h2>
          <.link
            navigate={~p"/manage/accounts/#{@record.user.id}/compose?locale=#{@locale}"}
            class="underline"
          >{gettext("Compose")}</.link>
          <p>
            {if @record.user.confirmed_at,
              do: gettext("Email confirmed"),
              else: gettext("Account created · email unconfirmed")}
          </p>

          <.form
            for={@form}
            id="managed-account-form"
            phx-change="edit"
            phx-submit="save"
            class="max-w-2xl space-y-4 rounded-xl border bg-white p-6"
          >
            <.input
              field={@form[:name]}
              label={gettext("Name")}
              errors={field_errors(@errors, "name")}
            />
            <.input
              field={@form[:group_id]}
              type="select"
              label={gettext("Incubator / group")}
              prompt={gettext("Unassigned")}
              options={Enum.map(@groups, &{&1.name, &1.id})}
              errors={field_errors(@errors, "group_id")}
            />
            <.input
              field={@form[:postal_code]}
              label={gettext("Postal code")}
              errors={field_errors(@errors, "postal_code")}
            />
            <.input
              field={@form[:city]}
              label={gettext("City")}
              errors={field_errors(@errors, "city")}
            />
            <.input
              field={@form[:notes]}
              type="textarea"
              label={gettext("Private organizer notes")}
              errors={field_errors(@errors, "notes")}
            />
            <.button>{gettext("Save account")}</.button>
          </.form>
          <details
            :if={@admin?}
            open={@confirm_role}
            id="account-access"
            class="rounded-xl border bg-white p-6"
          >
            <summary>
              {gettext("Access")} · {if @record.user.superadmin,
                do: gettext("Superadmin"),
                else: gettext("Account")}
            </summary>
            <button
              id="account-superadmin"
              phx-click={if @record.user.superadmin, do: "set-superadmin", else: "confirm-role"}
              phx-value-enabled={to_string(!@record.user.superadmin)}
              disabled={!@record.user.superadmin and is_nil(@record.user.confirmed_at)}
              class="mt-4 rounded-lg border px-4 py-2 disabled:opacity-40"
            >
              {if @record.user.superadmin,
                do: gettext("Remove role"),
                else: gettext("Make superadmin")}
            </button>
            <div
              :if={@confirm_role and !@record.user.superadmin}
              id="role-confirmation"
              class="mt-4 rounded border border-brand p-4"
            >
              <p>{gettext("Grant superadmin access and send the account an email notification?")}</p>
              <button
                type="button"
                phx-click="set-superadmin"
                phx-value-enabled="true"
                class="mt-3 rounded bg-brand px-4 py-2 font-bold"
              >{gettext("Grant access and notify")}</button>
            </div>
            <p>
              {gettext(
                "Only confirmed accounts can become superadmins. The last superadmin must retain access."
              )}
            </p>
            <h3 class="mt-4 font-bold">{gettext("Managed groups")}</h3>
            <p :for={manager <- @managers}>
              {manager.group.name}
              <button phx-click="revoke-manager" phx-value-id={manager.id}>{gettext("Remove")}</button>
            </p>
            <.form
              for={to_form(%{}, as: "manager")}
              phx-submit="assign-manager"
              id="account-manager-form"
            >
              <.input
                id="account-manager-group"
                name="manager[group_id]"
                value=""
                type="select"
                label={gettext("Group to manage")}
                options={Enum.map(@groups, &{&1.name, &1.id})}
              />
              <.button>{gettext("Assign manager")}</.button>
            </.form>
          </details>
          <section id="account-email-history" class="space-y-3 rounded-xl border bg-white p-6">
            <h2 class="text-xl font-bold">{gettext("Email history")}</h2>
            <p>
              {gettext(
                "PauseAI transactional emails and campaigns recorded by Brevo. Availability depends on provider retention. Delivered means accepted by the receiving mail server; opens and clicks are separate observations."
              )}
            </p>
            <.form
              for={to_form(@mail_filters, as: "history")}
              phx-submit="email-history"
              id="email-history-form"
              class="flex flex-wrap items-end gap-3"
            >
              <.input
                name="history[from]"
                value={@mail_filters["from"]}
                type="date"
                label={gettext("From date")}
                required
              />
              <.input
                name="history[to]"
                value={@mail_filters["to"]}
                type="date"
                label={gettext("To date")}
                required
              />
              <.input
                name="history[page]"
                value={@mail_filters["page"]}
                type="number"
                min="1"
                max="1000"
                label={gettext("History page")}
                required
              />
              <.button disabled={@mail_loading}>{gettext("Refresh history")}</.button>
            </.form>
            <p>
              {gettext(
                "Choose up to 90 days. Each page contains up to 100 transactional events and 10 campaigns. Older pages may contain further events for the same message."
              )}
            </p>
            <p :if={@mail_loading} role="status">{gettext("Loading email history…")}</p>
            <p :if={@mail_error} role="alert">{history_error(@mail_error)}</p>
            <div
              :for={source <- [:transactional, :campaigns]}
              :if={@mail_results[source]}
              id={"history-#{source}"}
            >
              <h3 class="font-bold">
                {if source == :transactional,
                  do: gettext("Transactional emails"),
                  else: gettext("Campaigns")}
              </h3>
              <p :if={@mail_results[source].refreshed_at}>
                {gettext("Last successful refresh")}:
                <VolunteerForms.timestamp
                  id={"history-refresh-#{source}"}
                  value={@mail_results[source].refreshed_at}
                  locale={@locale}
                />
              </p>
              <p :if={@mail_results[source].error} role="alert">
                {history_error(@mail_results[source].error)} {gettext(
                  "Previously retrieved results, if any, are shown below."
                )}
              </p>
              <p :if={@mail_results[source].partial}>
                {gettext("Partial history: some sender or campaign metadata could not be verified.")}
              </p>
              <p :if={@mail_results[source].rows == [] and !@mail_results[source].error}>
                {gettext("No matching emails in this range and page.")}
              </p>
              <div class="overflow-x-auto">
                <table class="w-full text-left">
                  <thead>
                    <tr>
                      <th>{gettext("Subject")}</th><th>{gettext("Sent")}</th><th>
                        {gettext("Provider events")}
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={{row, row_index} <- Enum.with_index(@mail_results[source].rows)}
                      class="border-t"
                    >
                      <td class="p-3">{row.subject || gettext("Subject unavailable")}</td>
                      <td class="p-3">
                        <.history_time
                          id={"mail-sent-#{source}-#{row_index}"}
                          value={row.sent_at}
                          locale={@locale}
                        />
                      </td>
                      <td class="p-3">
                        <p :for={{event, event_index} <- Enum.with_index(row.events)}>
                          {event_label(event.status)} ·
                          <.history_time
                            id={"mail-event-#{source}-#{row_index}-#{event_index}"}
                            value={event.at}
                            locale={@locale}
                          />
                        </p>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <p :if={@mail_results[source].more}>
                {gettext("More history is available on the next page.")}
              </p>
            </div>
          </section>
          <div :if={@record.signup} class="space-y-3">
            <h2 class="text-xl font-bold">{gettext("Invitations")}</h2>
            <p :for={invitation <- @record.signup.invitations}>
              {VolunteerForms.status(invitation.status)}
              <VolunteerForms.timestamp
                id={"account-invitation-#{invitation.id}"}
                value={invitation.inserted_at}
                locale={@locale}
              />
            </p>
            <.link
              :if={Enum.any?(@batches, &(&1.id == @record.signup.batch_id))}
              navigate={
                ~p"/manage/accounts/import?#{%{batch: @record.signup.batch_id, locale: @locale}}"
              }
              class="underline"
            >{gettext("View batch and invitation actions")}</.link>
          </div>
        <% else %>
          <nav class="flex flex-wrap gap-3" aria-label={gettext("Account actions")}>
            <.link
              navigate={~p"/manage/accounts/new?locale=#{@locale}"}
              class="rounded-lg border px-4 py-2"
            >{gettext("Add account")}</.link>
            <.link
              navigate={~p"/manage/accounts/import?locale=#{@locale}"}
              class="rounded-lg border px-4 py-2"
            >{gettext("Add multiple accounts")}</.link>
          </nav>
          <p id="account-count">
            {ngettext("%{count} account", "%{count} accounts", @count, count: @count)}
          </p>
          <.form for={to_form(%{}, as: "search")} phx-change="search" id="account-search">
            <.input
              name="search"
              id="account-search-input"
              value={@search}
              label={gettext("Search accounts")}
              phx-debounce="200"
            />
          </.form>
          <div class="overflow-x-auto">
            <table class="w-full text-left">
              <thead>
                <tr>
                  <th>{gettext("Name")}</th><th>{gettext("Email")}</th><th>
                    {gettext("Incubator / group")}
                  </th><th>{gettext("Status")}</th>
                </tr>
              </thead><tbody>
                <tr :for={record <- Enum.take(@records, 25)} class="border-t">
                  <td class="p-3">{record.user.name}</td><td class="p-3">
                    <.link
                      navigate={~p"/manage/accounts/#{record.user.id}?locale=#{@locale}"}
                      class="underline"
                    >{record.user.email}</.link>
                  </td><td class="p-3">{record.group && record.group.name}</td><td class="p-3">
                    {if record.user.confirmed_at,
                      do: gettext("Email confirmed"),
                      else: gettext("Account created · email unconfirmed")}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@records == []}>{gettext("No accounts found.")}</p>
          <nav class="flex gap-4" aria-label={gettext("Account pages")}>
            <.link
              :if={@page > 1}
              patch={~p"/manage/accounts?#{%{locale: @locale, q: @search, page: @page - 1}}"}
            >{gettext("Previous")}</.link>
            <span id="account-page">{gettext("Page %{page} of %{page_count}",
              page: @page,
              page_count: @pages
            )}</span>
            <.link
              :if={length(@records) > 25}
              patch={~p"/manage/accounts?#{%{locale: @locale, q: @search, page: @page + 1}}"}
            >{gettext("Next")}</.link>
          </nav>
          <section class="space-y-3">
            <h2 class="text-xl font-bold">{gettext("Saved batches and invitations")}</h2>
            <p :if={@batches == []}>{gettext("No saved batches yet.")}</p>
            <div :for={batch <- @batches}>
              <.link
                navigate={~p"/manage/accounts/import?#{%{batch: batch.id, locale: @locale}}"}
                class="underline"
              >{if batch.source == "", do: gettext("Untitled batch"), else: batch.source} · {if batch.state ==
                                                                                                  "draft",
                                                                                                do:
                                                                                                  gettext(
                                                                                                    "Draft"
                                                                                                  ),
                                                                                                else:
                                                                                                  gettext(
                                                                                                    "Confirmed"
                                                                                                  )}</.link>
            </div>
          </section>
        <% end %>
      </section>
    </Layouts.management>
    """
  end

  defp history_error(:invalid_range),
    do:
      gettext(
        "Choose valid dates spanning at most 90 days, ending no later than today, and a valid page."
      )

  defp history_error(:not_configured), do: gettext("Brevo history is not configured.")
  defp history_error(:unauthorized), do: gettext("You no longer have access to this account.")
  defp history_error(:rate_limited), do: gettext("Brevo is limiting requests. Retry shortly.")
  defp history_error(_), do: gettext("Email history could not refresh. Retry shortly.")

  attr :id, :string, required: true
  attr :value, :any, required: true
  attr :locale, :string, required: true

  defp history_time(assigns) do
    time =
      case DateTime.from_iso8601(assigns.value || "") do
        {:ok, time, _} -> time
        _ -> nil
      end

    assigns = assign(assigns, :time, time)

    ~H"""
    <VolunteerForms.timestamp :if={@time} id={@id} value={@time} locale={@locale} />
    <span :if={!@time}>{gettext("Time unavailable")}</span>
    """
  end

  defp event_label("requests"), do: gettext("Accepted")
  defp event_label("messagesSent"), do: gettext("Sent")
  defp event_label("delivered"), do: gettext("Delivered")
  defp event_label("opened"), do: gettext("Opened")
  defp event_label(value) when value in ["clicks", "clicked"], do: gettext("Clicked")

  defp event_label(value)
       when value in ["hardBounces", "hardBounce", "hard_bounce", "hardbounce"],
       do: gettext("Hard bounce")

  defp event_label(value)
       when value in ["softBounces", "softBounce", "soft_bounce", "softbounce"],
       do: gettext("Soft bounce")

  defp event_label("deferred"), do: gettext("Deferred")
  defp event_label("blocked"), do: gettext("Blocked")
  defp event_label("unsubscribed"), do: gettext("Unsubscribed")
  defp event_label(value) when value in ["spam", "complaints"], do: gettext("Complaint")
  defp event_label("loadedByProxy"), do: gettext("Loaded by proxy")
  defp event_label(_), do: gettext("Other provider event")

  defp field_errors(errors, field),
    do: if(errors[field], do: [VolunteerForms.error(errors[field])], else: [])
end
