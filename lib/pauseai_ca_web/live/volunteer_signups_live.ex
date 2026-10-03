defmodule PauseAiCaWeb.VolunteerSignupsLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Volunteers
  alias PauseAiCa.Volunteers.Input
  alias PauseAiCaWeb.VolunteerForms

  @impl true
  def mount(params, _session, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    socket = assign(socket, :locale, locale)
    scope = socket.assigns.current_scope

    if Volunteers.allowed?(scope) do
      groups = Volunteers.groups(scope)

      {:ok,
       socket
       |> assign(
         page_title: gettext("Add accounts"),
         single?: socket.assigns.live_action == :new,
         groups: groups,
         admin?: Volunteers.superadmin?(scope),
         management_open?: false,
         managers: Volunteers.managers(scope),
         batches: Volunteers.list_batches(scope),
         batch: nil,
         rows: [],
         source: "",
         default_group_id: default_group(scope),
         step: "rows",
         csv: nil,
         csv_mapping: %{},
         reviewed: [],
         results: [],
         events: [],
         search: "",
         page: 1,
         row_key: nil,
         sending?: false,
         poll_ref: nil,
         saved?: false,
         form: to_form(%{}, as: "signup")
       )
       |> allow_upload(:csv, accept: ~w(.csv), max_entries: 1, max_file_size: 5_000_000)}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Organizer access required."))
       |> redirect(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if params["batch"] do
      case Volunteers.get_batch(socket.assigns.current_scope, params["batch"]) do
        {:ok, batch} ->
          {:noreply, load_batch(socket, batch)}

        _ ->
          {:noreply,
           socket
           |> put_flash(:error, gettext("This draft is unavailable."))
           |> push_patch(
             to:
               if(socket.assigns.single?,
                 do: ~p"/manage/accounts/new?locale=#{socket.assigns.locale}",
                 else: signup_path(nil, socket.assigns.locale)
               )
           )}
      end
    else
      {:noreply,
       if(socket.assigns.single? && socket.assigns.rows == [],
         do: update_rows(socket, [Input.normalize(%{"selected" => true})]),
         else: socket
       )}
    end
  end

  @impl true
  def handle_event("create-group", %{"group" => attrs}, socket) do
    case Volunteers.create_group(socket.assigns.current_scope, attrs) do
      {:ok, _} -> {:noreply, reload_groups(socket)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Enter a unique group name."))}
    end
  end

  def handle_event("assign-manager", %{"manager" => attrs}, socket) do
    case Volunteers.assign_manager(
           socket.assigns.current_scope,
           attrs["group_id"],
           attrs["email"]
         ) do
      {:ok, _} ->
        {:noreply, reload_groups(socket)}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Choose a group and a confirmed account."))}
    end
  end

  def handle_event("revoke-manager", %{"id" => id}, socket) do
    Volunteers.revoke_manager(socket.assigns.current_scope, id)
    {:noreply, reload_groups(socket)}
  end

  def handle_event("new", _params, socket) do
    {:noreply,
     socket
     |> assign(
       batches: Volunteers.list_batches(socket.assigns.current_scope),
       batch: nil,
       rows: [],
       reviewed: [],
       results: [],
       source: "",
       default_group_id: default_group(socket.assigns.current_scope),
       csv: nil,
       csv_mapping: %{},
       page: 1,
       step: "rows",
       row_key: nil,
       saved?: false
     )
     |> push_patch(to: signup_path(nil, socket.assigns.locale))}
  end

  def handle_event("validate-upload", _, socket), do: {:noreply, socket}

  def handle_event("upload", _, socket) do
    results =
      consume_uploaded_entries(socket, :csv, fn %{path: path}, _ -> {:ok, File.read!(path)} end)

    with [contents] <- results, {:ok, csv} <- Input.csv(contents) do
      {:noreply, assign(socket, :csv, csv)}
    else
      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Choose a valid UTF-8 CSV with at most 1,000 rows."))}
    end
  end

  def handle_event("map-csv", %{"mapping" => mapping}, socket) do
    mapping =
      socket.assigns.csv.headers
      |> Enum.with_index()
      |> Enum.map(fn {_, i} -> mapping[to_string(i)] end)

    case Input.mapped(socket.assigns.csv, mapping) do
      {:ok, rows} ->
        {:noreply,
         update_rows(
           assign(socket,
             csv: nil,
             csv_mapping: %{"headers" => socket.assigns.csv.headers, "destinations" => mapping}
           ),
           rows
         )}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Map Email once and use each destination column at most once.")
         )}
    end
  end

  def handle_event("paste", %{"paste" => %{"text" => text}}, socket) do
    case Input.paste(text) do
      {:ok, rows} -> {:noreply, update_rows(socket, socket.assigns.rows ++ rows)}
      _ -> {:noreply, put_flash(socket, :error, gettext("Use at most 1,000 rows."))}
    end
  end

  def handle_event("add-row", _, socket),
    do: {:noreply, update_rows(socket, socket.assigns.rows ++ [Input.normalize(%{})])}

  def handle_event("remove-row", %{"key" => key}, socket),
    do: {:noreply, update_rows(socket, Enum.reject(socket.assigns.rows, &(&1["key"] == key)))}

  def handle_event("change", %{"signup" => params} = event, socket) do
    # Full form payloads can contain stale server-driven checkbox values. Apply
    # the edited field only; reconnect recovery without a target restores all.
    target = event["_target"]

    row_params =
      case target do
        ["signup", "rows", key, field] ->
          %{key => Map.take(get_in(params, ["rows", key]) || %{}, [field])}

        ["signup", field] when field in ["source", "default_group_id"] ->
          %{}

        _ ->
          params["rows"] || %{}
      end

    rows = merge_rows(socket.assigns.rows, row_params)

    source =
      if target in [nil, ["signup"], ["signup", "source"]],
        do: params["source"] || "",
        else: socket.assigns.source

    default =
      if target in [nil, ["signup"], ["signup", "default_group_id"]],
        do: params["default_group_id"],
        else: socket.assigns.default_group_id

    {:noreply,
     socket
     |> assign(source: source, default_group_id: if(default == "", do: nil, else: default))
     |> update_rows(rows)}
  end

  def handle_event("toggle-management", _, socket),
    do: {:noreply, assign(socket, :management_open?, not socket.assigns.management_open?)}

  def handle_event("search", %{"search" => search}, socket),
    do: {:noreply, assign(socket, search: String.downcase(search), page: 1)}

  def handle_event("select-valid", _, socket) do
    valid =
      socket.assigns.reviewed |> Enum.filter(&(&1.errors == %{})) |> MapSet.new(& &1.row["key"])

    rows =
      Enum.map(socket.assigns.rows, &Map.put(&1, "selected", MapSet.member?(valid, &1["key"])))

    {:noreply, update_rows(socket, rows)}
  end

  def handle_event("details", %{"key" => key}, socket) do
    row = Enum.find(socket.assigns.rows, &(&1["key"] == key))

    if row,
      do:
        {:noreply,
         assign(socket, step: "contact", row_key: key, form: to_form(row, as: "profile"))},
      else: {:noreply, socket}
  end

  def handle_event("profile-change", %{"profile" => values}, socket) do
    rows =
      Enum.map(socket.assigns.rows, fn row ->
        if row["key"] == socket.assigns.row_key, do: Map.merge(row, values), else: row
      end)

    {:noreply,
     socket
     |> update_rows(rows)
     |> assign(
       :form,
       to_form(Enum.find(rows, &(&1["key"] == socket.assigns.row_key)), as: "profile")
     )}
  end

  def handle_event("next-details", _, socket),
    do:
      {:noreply,
       assign(
         socket,
         :step,
         if(socket.assigns.step == "contact", do: "contribution", else: "rows")
       )}

  def handle_event("rows", _, socket), do: {:noreply, assign(socket, :step, "rows")}

  def handle_event("save", _, socket), do: persist(socket, false)
  def handle_event("save-exit", _, socket), do: persist(socket, false, true)

  def handle_event("page", %{"page" => page}, socket),
    do: {:noreply, assign(socket, :page, max(1, String.to_integer(page)))}

  def handle_event("resend", %{"id" => id}, socket) do
    case Volunteers.resend(socket.assigns.current_scope, id) do
      {:ok, _} -> handle_event("confirm", %{}, socket)
      _ -> {:noreply, put_flash(socket, :error, gettext("This invitation cannot be resent."))}
    end
  end

  def handle_event("review", _, socket), do: persist(assign(socket, :step, "review"), true)

  def handle_event("discard", _, socket) do
    if socket.assigns.batch,
      do: Volunteers.discard_draft(socket.assigns.current_scope, socket.assigns.batch.id)

    handle_event("new", %{}, socket)
  end

  def handle_event("confirm", _, socket) do
    if socket.assigns.batch do
      case Volunteers.confirm(socket.assigns.current_scope, socket.assigns.batch.id) do
        {:ok, batch} ->
          scope = socket.assigns.current_scope

          {:noreply,
           socket
           |> load_batch(batch)
           |> assign(:sending?, true)
           |> start_async(:dispatch, fn -> Volunteers.dispatch_batch(scope, batch.id) end)}

        _ ->
          {:noreply,
           put_flash(
             socket,
             :error,
             gettext("The selection changed or is not authorized. Review the rows again.")
           )}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("retry", %{"id" => id}, socket) do
    case Volunteers.retry(socket.assigns.current_scope, id) do
      {:ok, _} -> handle_event("confirm", %{}, socket)
      _ -> {:noreply, put_flash(socket, :error, gettext("This invitation cannot be retried."))}
    end
  end

  def handle_event("reconcile", %{"reconcile" => values}, socket) do
    case Volunteers.reconcile(
           socket.assigns.current_scope,
           values["id"],
           values["outcome"],
           values["reference"]
         ) do
      {:ok, _} ->
        {:noreply, load_batch(socket, socket.assigns.batch)}

      _ ->
        {:noreply,
         put_flash(socket, :error, gettext("Record the verified provider outcome and reference."))}
    end
  end

  def handle_event("refresh", _, socket), do: {:noreply, load_batch(socket, socket.assigns.batch)}

  @impl true
  def handle_info(:refresh_results, socket) do
    {:noreply,
     if(socket.assigns.batch, do: load_batch(socket, socket.assigns.batch), else: socket)}
  end

  @impl true
  def handle_async(:dispatch, _, socket),
    do: {:noreply, socket |> load_batch(socket.assigns.batch) |> assign(:sending?, false)}

  defp persist(socket, review?, exit? \\ false) do
    a = socket.assigns
    rows = Enum.map(a.rows, &Map.put(&1, "wizard_row", &1["key"] == a.row_key))

    attrs = %{
      "rows" => rows,
      "entry_mode" => if(a.single?, do: "single", else: "multiple"),
      "csv_mapping" => a.csv_mapping,
      "source" => a.source,
      "default_group_id" => a.default_group_id,
      "step" => a.step,
      "wizard_row" => a.row_key
    }

    case Volunteers.save_draft(a.current_scope, a.batch, attrs) do
      {:ok, batch} ->
        socket =
          socket
          |> assign(batch: batch, saved?: true, batches: Volunteers.list_batches(a.current_scope))
          |> put_flash(:info, gettext("Draft saved. You can resume after signing in."))

        socket =
          if exit?,
            do: push_navigate(socket, to: ~p"/dashboard"),
            else: push_patch(socket, to: signup_path(batch, socket.assigns.locale))

        {:noreply, if(review?, do: assign(socket, :step, "review"), else: socket)}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Draft not saved. Keep this page open, check access and retry.")
         )}
    end
  end

  defp load_batch(socket, batch) do
    socket
    |> assign(
      batches: Volunteers.list_batches(socket.assigns.current_scope),
      batch: batch,
      single?: batch.entry_mode == "single",
      rows: batch.rows,
      csv_mapping: batch.csv_mapping,
      default_group_id: batch.default_group_id,
      source: batch.source,
      step: batch.step,
      results: Volunteers.results(socket.assigns.current_scope, batch.id),
      events: Volunteers.events(socket.assigns.current_scope, batch.id),
      saved?: true,
      row_key: batch.wizard_row,
      form: to_form(Enum.find(batch.rows, %{}, &(&1["key"] == batch.wizard_row)), as: "profile")
    )
    |> refresh_review()
    |> poll_results()
  end

  defp poll_results(socket) do
    if socket.assigns.poll_ref, do: Process.cancel_timer(socket.assigns.poll_ref)

    pending? =
      Enum.any?(socket.assigns.results, fn signup ->
        Enum.any?(signup.invitations, &(&1.status in ["queued", "sending"]))
      end)

    timer =
      if connected?(socket) and pending?, do: Process.send_after(self(), :refresh_results, 1_000)

    assign(socket, poll_ref: timer, sending?: pending?)
  end

  defp update_rows(socket, rows) do
    rows =
      Enum.map(rows, fn row ->
        group =
          Enum.find(
            socket.assigns.groups,
            &(&1.id == row["group_id"] or
                String.downcase(&1.name) == String.downcase(row["group_id"] || ""))
          )

        if group, do: Map.put(row, "group_id", group.id), else: row
      end)

    socket |> assign(rows: rows, saved?: false) |> refresh_review()
  end

  defp refresh_review(socket),
    do:
      assign(
        socket,
        :reviewed,
        Volunteers.review(
          socket.assigns.current_scope,
          socket.assigns.rows,
          socket.assigns.default_group_id
        )
      )

  defp reload_groups(socket),
    do:
      assign(socket,
        groups: Volunteers.groups(socket.assigns.current_scope),
        managers: Volunteers.managers(socket.assigns.current_scope)
      )

  defp merge_rows(rows, params),
    do:
      Enum.map(rows, fn row ->
        Input.normalize(Map.merge(row, Map.get(params, row["key"], %{})))
      end)

  defp entry_path(batch, single?, locale) do
    other_locale =
      case locale do
        "fr" -> "en"
        _ -> "fr"
      end

    if single? && is_nil(batch),
      do: ~p"/manage/accounts/new?locale=#{other_locale}",
      else: signup_path(batch, other_locale)
  end

  defp signup_path(nil, locale), do: ~p"/manage/accounts/import?locale=#{locale}"

  defp signup_path(batch, locale),
    do: ~p"/manage/accounts/import?#{%{batch: batch.id, locale: locale}}"

  defp default_group(scope),
    do:
      if(Volunteers.superadmin?(scope),
        do: nil,
        else: (List.first(Volunteers.groups(scope)) || %{}) |> Map.get(:id)
      )

  defp page_rows(rows, search, page),
    do: rows |> Enum.filter(&visible?(&1, search)) |> Enum.drop((page - 1) * 25) |> Enum.take(25)

  defp preview,
    do:
      PauseAiCa.Accounts.UserNotifier.volunteer_invitation(
        %{email: "volunteer@example.org"},
        "https://example.org/sign-in-preview"
      )

  defp visible?(entry, search),
    do:
      search == "" or
        String.contains?(String.downcase(entry.row["email"] <> " " <> entry.row["name"]), search)

  defp selected(reviewed), do: Enum.filter(reviewed, & &1.row["selected"])

  defp row_options(groups, row) do
    options = [{gettext("Use batch default"), ""} | Enum.map(groups, &{&1.name, &1.id})]

    if row["group_id"] != "" and not Enum.any?(groups, &(&1.id == row["group_id"])),
      do: options ++ [{row["group_id"], row["group_id"]}],
      else: options
  end

  defp group_name(nil), do: "—"
  defp group_name(:invalid), do: "—"
  defp group_name(group), do: group.name

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      promote_warning_shot={false}
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={entry_path(@batch, @single?, @locale)}
    >
      <section
        class={["mx-auto space-y-6 px-5 py-12", if(@single?, do: "max-w-3xl", else: "max-w-7xl")]}
        id="volunteer-signups"
        lang={@locale}
      >
        <header>
          <.link navigate={~p"/manage/accounts?locale=#{@locale}"} class="underline">{gettext(
            "Accounts"
          )}</.link><h1 class="mt-3 text-4xl font-bold">
            {if @single?, do: gettext("Add account"), else: gettext("Add multiple accounts")}
          </h1>
          <p :if={!@single?} class="mt-3">
            {gettext(
              "Enter volunteer signup sheets, review the accounts and send individual sign-in invitations."
            )}
          </p>
        </header>
        <details
          :if={@admin? && !@single?}
          class="rounded-xl border border-stone-200 bg-white p-5"
          id="group-management"
          open={@management_open?}
        >
          <summary phx-click="toggle-management" class="cursor-pointer font-bold">
            {gettext("Groups and managers")}
          </summary>
          <div class="mt-4 grid gap-6 md:grid-cols-2">
            <.form
              for={to_form(%{}, as: "group")}
              phx-submit="create-group"
              id="create-group"
              class="space-y-3"
            >
              <.input
                name="group[name]"
                id="group-name"
                value=""
                label={gettext("Group name")}
                required
              />
              <.button>{gettext("Create group")}</.button>
            </.form>
            <.form
              for={to_form(%{}, as: "manager")}
              phx-submit="assign-manager"
              id="assign-manager"
              class="space-y-3"
            >
              <.input
                name="manager[group_id]"
                id="manager-group"
                value=""
                type="select"
                label={gettext("Group to manage")}
                options={Enum.map(@groups, &{&1.name, &1.id})}
              />
              <.input
                name="manager[email]"
                id="manager-email"
                value=""
                type="email"
                label={gettext("Manager email")}
                required
              />
              <.button>{gettext("Assign manager")}</.button>
            </.form>
          </div>
          <ul class="mt-4 space-y-2">
            <li :for={manager <- @managers}>
              {manager.user.email} · {manager.group.name}
              <button
                type="button"
                phx-click="revoke-manager"
                phx-value-id={manager.id}
                class="ml-3 underline"
              >{gettext("Revoke manager")}</button>
            </li>
          </ul>
        </details>
        <nav :if={!@single?} class="flex flex-wrap gap-3" aria-label={gettext("Signup batches")}>
          <button type="button" phx-click="new" class="rounded-lg border px-4 py-2">{gettext(
            "New batch"
          )}</button>
          <.link
            :for={batch <- @batches}
            patch={signup_path(batch, @locale)}
            class="rounded-lg border px-4 py-2"
          >
            {if batch.source == "", do: gettext("Untitled batch"), else: batch.source} · {if batch.state ==
                                                                                               "draft",
                                                                                             do:
                                                                                               gettext(
                                                                                                 "Draft"
                                                                                               ),
                                                                                             else:
                                                                                               gettext(
                                                                                                 "Confirmed"
                                                                                               )}
          </.link>
        </nav>
        <%= if @batch && @batch.state == "confirmed" do %>
          <div id="batch-result" class="space-y-4 rounded-xl border bg-white p-6">
            <h2 class="text-2xl font-bold">{gettext("Batch result")}</h2>
            <p :if={@sending?} role="status">
              {gettext("Sending invitations. You can return to this batch to see the result.")}
            </p>
            <.button phx-click="refresh">{gettext("Refresh results")}</.button>
            <article
              :for={signup <- @results}
              id={"signup-#{signup.id}"}
              class="rounded-lg border p-4"
            >
              <p class="font-semibold">
                {signup.user.name || signup.email} · {signup.email} · {group_name(signup.group)}
              </p>
              <p>
                {if signup.user.confirmed_at,
                  do: gettext("Email confirmed"),
                  else: gettext("Account created · email unconfirmed")}
              </p>
              <details>
                <summary>{gettext("Private organizer notes")}</summary><p class="whitespace-pre-wrap">
                  {signup.notes}
                </p>
              </details>
              <div :for={invitation <- signup.invitations} class="mt-3 border-t pt-3">
                <p>
                  <.dev_mailbox_link :if={invitation.status == "accepted"} />
                  {VolunteerForms.status(invitation.status)} ·
                  <VolunteerForms.timestamp
                    id={"invitation-time-#{invitation.id}"}
                    value={invitation.attempted_at}
                    locale={@locale}
                  />
                </p>
                <p :if={invitation.provider_id}>
                  {gettext("Provider reference")}: <code>{invitation.provider_id}</code>
                </p>
                <.button
                  :if={invitation.status == "accepted"}
                  phx-click="resend"
                  phx-value-id={invitation.id}
                  data-confirm={gettext("Send another sign-in invitation to this volunteer?")}
                >{gettext("Resend invitation")}</.button>
                <.button
                  :if={invitation.status == "failed"}
                  phx-click="retry"
                  phx-value-id={invitation.id}
                >{gettext("Retry invitation")}</.button>
                <.form
                  :if={@admin? && invitation.status == "unknown"}
                  for={to_form(%{}, as: "reconcile")}
                  phx-submit="reconcile"
                  class="mt-3 space-y-3"
                >
                  <input type="hidden" name="reconcile[id]" value={invitation.id} />
                  <.input
                    type="select"
                    name="reconcile[outcome]"
                    id={"outcome-#{invitation.id}"}
                    value="accepted"
                    label={gettext("Verified provider outcome")}
                    options={[
                      {gettext("Accepted by email provider"), "accepted"},
                      {gettext("Failed"), "failed"}
                    ]}
                  />
                  <.input
                    name="reconcile[reference]"
                    id={"reference-#{invitation.id}"}
                    value=""
                    label={gettext("Provider verification reference")}
                    required
                  />
                  <.button>{gettext("Record reconciliation")}</.button>
                </.form>
              </div>
            </article>
            <details id="batch-activity">
              <summary>{gettext("Batch activity")}</summary>
              <ol>
                <li :for={event <- @events}>
                  {VolunteerForms.action(event.action)} ·
                  <VolunteerForms.timestamp
                    id={"event-time-#{event.id}"}
                    value={event.inserted_at}
                    locale={@locale}
                  /> · {event.actor && event.actor.email}
                </li>
              </ol>
            </details>
          </div>
        <% else %>
          <%= cond do %>
            <% @step in ["contact", "contribution"] -> %>
              <.form
                for={@form}
                phx-change="profile-change"
                phx-submit="next-details"
                id="row-details"
                class="space-y-5 rounded-xl border bg-white p-6"
              >
                <h2 class="text-2xl font-bold">{gettext("Optional details")}</h2>
                <p>
                  {if @step == "contact",
                    do: gettext("1 Contact → 2 Contribution → 3 Review"),
                    else: gettext("2 Contribution → 3 Review")}
                </p>
                <VolunteerForms.profile_fields
                  form={@form}
                  step={@step}
                  errors={Input.profile_errors(@form.params)}
                />
                <div class="flex flex-wrap gap-3">
                  <.button>{gettext("Next")}</.button><.button type="button" phx-click="save-exit">{gettext(
                    "Save and exit"
                  )}</.button><button type="button" phx-click="rows" class="underline">{gettext(
                    "Back to rows"
                  )}</button>
                </div>
              </.form>
            <% @step == "review" -> %>
              <div id="signup-review" class="space-y-5 rounded-xl border bg-white p-6">
                <h2 class="text-2xl font-bold">{gettext("Review and invite")}</h2>
                <p>
                  {ngettext(
                    "%{count} selected volunteer",
                    "%{count} selected volunteers",
                    length(selected(@reviewed)),
                    count: length(selected(@reviewed))
                  )}
                </p>
                <ul>
                  <li :for={entry <- selected(@reviewed)}>
                    {entry.row["name"]} · {entry.row["email"]} · {group_name(entry.group)} · {VolunteerForms.status(
                      entry.status
                    )}
                    <p :for={{_field, reason} <- entry.errors} class="text-red-700">
                      {VolunteerForms.error(reason)}
                    </p>
                  </li>
                </ul>
                <article class="rounded-lg border bg-stone-50 p-4" id="invitation-preview">
                  <h3 class="font-bold">{gettext("Invitation preview")}</h3>
                  <p>
                    {gettext(
                      "One individual bilingual email per selected volunteer, with a private sign-in link. Organizer notes stay private."
                    )}
                  </p>
                  <p>{preview().subject} · {elem(preview().from, 1)}</p>
                  <iframe
                    title={gettext("Invitation preview")}
                    srcdoc={preview().html_body}
                    sandbox=""
                    class="mt-3 h-[38rem] w-full border-0"
                  ></iframe>
                </article>
                <p>
                  {gettext(
                    "Confirming creates or matches these accounts and sends their invitations now."
                  )}
                </p>
                <div class="flex gap-3">
                  <.button
                    phx-click="confirm"
                    disabled={
                      selected(@reviewed) == [] || Enum.any?(selected(@reviewed), &(&1.errors != %{}))
                    }
                  >{gettext("Create accounts and send invitations")}</.button><button
                    type="button"
                    phx-click="rows"
                    class="underline"
                  >{gettext("Back to rows")}</button>
                </div>
              </div>
            <% true -> %>
              <details :if={!@single?} class="rounded-xl border bg-white p-5" open>
                <summary class="font-semibold">{gettext("Paste rows or upload CSV")}</summary>
                <.form
                  for={to_form(%{}, as: "paste")}
                  id="paste-rows"
                  phx-submit="paste"
                  class="mt-4 space-y-3"
                >
                  <.input
                    type="textarea"
                    name="paste[text]"
                    id="paste-text"
                    value=""
                    label={gettext("Paste spreadsheet rows")}
                    placeholder={
                      gettext("Name, email, postal code, group, notes — separated by tabs")
                    }
                  />
                  <.button>{gettext("Add pasted rows")}</.button>
                </.form>
                <.form
                  for={to_form(%{}, as: "upload")}
                  id="upload-csv"
                  phx-change="validate-upload"
                  phx-submit="upload"
                  class="mt-5 space-y-3"
                >
                  <label for={@uploads.csv.ref}>{gettext("CSV file")}</label><.live_file_input upload={
                    @uploads.csv
                  } />
                  <p :for={error <- upload_errors(@uploads.csv)} class="text-red-700">
                    {inspect(error)}
                  </p>
                  <.button>{gettext("Map CSV columns")}</.button>
                </.form>
              </details>
              <.form
                :if={@csv}
                for={to_form(%{}, as: "mapping")}
                id="csv-mapping"
                phx-submit="map-csv"
                class="space-y-3 rounded-xl border bg-white p-5"
              >
                <h2 class="text-xl font-bold">{gettext("Map CSV columns")}</h2>
                <.input
                  :for={{header, i} <- Enum.with_index(@csv.headers)}
                  type="select"
                  name={"mapping[#{i}]"}
                  id={"mapping-#{i}"}
                  value={Enum.at(@csv.mapping, i)}
                  label={header}
                  options={[
                    {gettext("Ignore column"), ""}
                    | Enum.map(Input.fields(), &{VolunteerForms.label(&1), &1})
                  ]}
                />
                <.button>{gettext("Open editable rows")}</.button>
              </.form>
              <.form
                :if={!@single?}
                for={to_form(%{}, as: "search")}
                phx-change="search"
                id="search-signups"
              >
                <.input
                  name="search"
                  id="signup-search"
                  value={@search}
                  label={gettext("Search rows")}
                />
              </.form>
              <.form
                for={to_form(%{}, as: "signup")}
                phx-change="change"
                phx-submit="save"
                id="signup-grid"
                class="space-y-4 rounded-xl border bg-white p-5"
              >
                <div class={if @single?, do: "space-y-4", else: "grid gap-4 sm:grid-cols-2"}>
                  <.input
                    :if={!@single?}
                    name="signup[source]"
                    id="signup-source"
                    value={@source}
                    label={gettext("Source label")}
                  />
                  <.input
                    name="signup[default_group_id]"
                    id="signup-default-group"
                    value={@default_group_id || ""}
                    type="select"
                    label={
                      if @single?,
                        do: gettext("Incubator / group"),
                        else: gettext("Default incubator / group")
                    }
                    options={[{gettext("Choose a group"), ""} | Enum.map(@groups, &{&1.name, &1.id})]}
                  />
                </div>
                <p :if={!@single?}>
                  {gettext(
                    "Email is required. Add names and locations when available. Row overrides stay unchanged when the default group changes."
                  )}
                </p>
                <div :if={!@single?} class="flex flex-wrap items-center gap-3">
                  <button type="button" phx-click="add-row" class="rounded-lg border px-3 py-2">{gettext(
                    "Add row"
                  )}</button><button
                    type="button"
                    phx-click="select-valid"
                    class="rounded-lg border px-3 py-2"
                  >{gettext("Select eligible rows")}</button><span id="signup-selected">{ngettext(
                    "%{count} selected",
                    "%{count} selected",
                    length(selected(@reviewed)),
                    count: length(selected(@reviewed))
                  )}</span>
                </div>
                <div :if={!@single?} class="overflow-x-auto">
                  <table class="w-full text-sm">
                    <thead>
                      <tr>
                        <th>{gettext("Select")}</th><th>{gettext("Name")}</th><th>
                          {gettext("Email")}
                        </th><th>{gettext("Postal code")}</th><th>{gettext("Incubator / group")}</th><th>
                          {gettext("Private organizer notes")}
                        </th><th>{gettext("Details")}</th>
                      </tr>
                    </thead>
                    <tbody>
                      <tr
                        :for={entry <- page_rows(@reviewed, @search, @page)}
                        id={"row-#{entry.row["key"]}"}
                        class="border-t align-top"
                      >
                        <% row = entry.row %>
                        <% row_form = to_form(row, as: "signup[rows][#{row["key"]}]") %>
                        <td class="p-2">
                          <.input
                            field={row_form[:selected]}
                            type="checkbox"
                            aria-label={gettext("Select %{email}", email: row["email"])}
                            disabled={entry.errors != %{}}
                          />
                        </td>
                        <td class="min-w-36 p-2">
                          <.input field={row_form[:name]} label={gettext("Name")} /><p
                            :if={row["name"] == ""}
                            class="text-amber-800"
                          >
                            {gettext("Name missing")}
                          </p>
                        </td>
                        <td class="min-w-52 p-2">
                          <.input
                            field={row_form[:email]}
                            label={gettext("Email")}
                            aria-invalid={Map.has_key?(entry.errors, "email")}
                            aria-describedby={"email-error-#{row["key"]}"}
                          /><p id={"email-error-#{row["key"]}"} class="text-red-700">
                            {if entry.errors["email"], do: VolunteerForms.error(entry.errors["email"])}
                          </p><p>{VolunteerForms.status(entry.status)}</p>
                        </td>
                        <td class="min-w-36 p-2">
                          <.input
                            field={row_form[:postal_code]}
                            label={gettext("Postal code")}
                            aria-invalid={Map.has_key?(entry.errors, "postal_code")}
                            aria-describedby={"postal-error-#{row["key"]}"}
                          /><p id={"postal-error-#{row["key"]}"} class="text-red-700">
                            {if entry.errors["postal_code"],
                              do: VolunteerForms.error(entry.errors["postal_code"])}
                          </p>
                        </td>
                        <td class="min-w-48 p-2">
                          <.input
                            field={row_form[:group_id]}
                            type="select"
                            label={gettext("Row group")}
                            options={row_options(@groups, row)}
                          /><p>
                            {group_name(entry.group)} · {if row["group_id"] == "",
                              do: gettext("Inherited"),
                              else: gettext("Override")}
                          </p><p :if={entry.errors["group_id"]} class="text-red-700">
                            {VolunteerForms.error(entry.errors["group_id"])}
                          </p><p
                            :if={
                              row["postal_code"] == "" && row["group_id"] == "" && !@default_group_id
                            }
                            class="text-amber-800"
                          >
                            {gettext("Location missing")}
                          </p>
                        </td>
                        <td class="min-w-44 p-2">
                          <.input
                            field={row_form[:notes]}
                            type="textarea"
                            label={gettext("Private organizer notes")}
                          />
                        </td>
                        <td class="space-y-3 p-2">
                          <button
                            type="button"
                            phx-click="details"
                            phx-value-key={row["key"]}
                            class="underline"
                          >{gettext("Optional details")}</button><button
                            type="button"
                            phx-click="remove-row"
                            phx-value-key={row["key"]}
                            class="underline"
                          >{gettext("Remove row")}</button><p
                            :for={
                              {field, reason} <-
                                Map.drop(entry.errors, ~w(email postal_code group_id))
                            }
                            class="text-red-700"
                          >
                            {VolunteerForms.label(field)}: {VolunteerForms.error(reason)}
                          </p>
                        </td>
                      </tr>
                    </tbody>
                  </table>
                </div>
                <div :for={entry <- @reviewed} :if={@single?} class="max-w-2xl space-y-4">
                  <% row_form = to_form(entry.row, as: "signup[rows][#{entry.row["key"]}]") %>
                  <input type="hidden" name={row_form[:selected].name} value="true" />
                  <.input
                    :for={field <- ~w(name email postal_code notes)}
                    field={row_form[String.to_existing_atom(field)]}
                    label={VolunteerForms.label(field)}
                    type={
                      if field == "notes",
                        do: "textarea",
                        else: if(field == "email", do: "email", else: "text")
                    }
                    errors={
                      if entry.errors[field],
                        do: [VolunteerForms.error(entry.errors[field])],
                        else: []
                    }
                  />
                  <p :if={entry.errors["group_id"]} class="text-red-700">
                    {VolunteerForms.error(entry.errors["group_id"])}
                  </p>
                  <button
                    type="button"
                    phx-click="details"
                    phx-value-key={entry.row["key"]}
                    class="underline"
                  >{gettext("Optional details")}</button>
                </div>
                <nav :if={!@single?} class="flex gap-3" aria-label={gettext("Row pages")}>
                  <button
                    type="button"
                    phx-click="page"
                    phx-value-page={@page - 1}
                    disabled={@page == 1}
                  >{gettext("Previous")}</button>
                  <span>{@page}</span>
                  <button
                    type="button"
                    phx-click="page"
                    phx-value-page={@page + 1}
                    disabled={length(Enum.filter(@reviewed, &visible?(&1, @search))) <= @page * 25}
                  >{gettext("Next")}</button>
                </nav>
                <div class="flex flex-wrap gap-3">
                  <.button>{gettext("Save draft")}</.button><.button type="button" phx-click="review">{gettext(
                    "Review and invite"
                  )}</.button><button
                    type="button"
                    phx-click="discard"
                    data-confirm={gettext("Discard this unsent draft?")}
                    class="underline"
                  >{gettext("Discard draft")}</button>
                </div>
                <p role="status">
                  {if @saved?,
                    do: gettext("Saved"),
                    else: gettext("Unsaved changes — save before leaving")}
                </p>
              </.form>
          <% end %>
        <% end %>
      </section>
    </Layouts.app>
    """
  end
end
