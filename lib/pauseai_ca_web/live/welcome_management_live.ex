defmodule PauseAiCaWeb.WelcomeManagementLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Welcome

  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Application.get_env(:pauseai_ca, :welcome_calls_enabled, false) do
      if connected?(socket), do: Process.send_after(self(), :refresh_access, 30_000)

      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Welcome calls"),
         groups: [],
         group_id: nil,
         sessions: [],
         record: nil,
         hosts: [],
         candidates: %{included: [], excluded: []},
         events: [],
         form: to_form(%{}, as: "session"),
         key: Ecto.UUID.generate(),
         error: nil,
         editing: false
       )}
    else
      {:ok, redirect(socket, to: ~p"/dashboard")}
    end
  end

  def handle_params(params, _, socket) do
    scope = socket.assigns.current_scope
    groups = Welcome.groups(scope)
    gid = params["group"] || (List.first(groups) && List.first(groups).id)

    with true <- Enum.any?(groups, &(&1.id == gid)),
         {:ok, sessions} <- Welcome.list(scope, gid),
         {:ok, hosts} <- Welcome.hosts(scope, gid),
         {:ok, candidates} <- Welcome.candidates(scope, gid),
         {:ok, record} <-
           if(params["id"], do: Welcome.get(scope, gid, params["id"]), else: {:ok, nil}) do
      {:ok, events} = if(record, do: Welcome.activity(scope, gid, record.id), else: {:ok, []})

      {:noreply,
       assign(socket,
         groups: groups,
         group_id: gid,
         sessions: sessions,
         hosts: hosts,
         candidates: candidates,
         record: record,
         events: events,
         editing: socket.assigns.live_action != :index,
         form:
           to_form(if(record, do: values(record), else: defaults(hosts, socket.assigns.locale)),
             as: "session"
           ),
         key: Ecto.UUID.generate(),
         error: nil
       )}
    else
      _ -> {:noreply, denied(socket)}
    end
  end

  def handle_event("group", %{"group" => id}, socket),
    do: {:noreply, push_patch(socket, to: list_path(id, socket.assigns.locale))}

  def handle_event("save-session", %{"session" => attrs, "_welcome_ref" => ref}, socket) do
    a = socket.assigns

    if ref != form_ref(a) do
      {:noreply, socket}
    else
      result =
        with {:ok, start} <- Welcome.local_time(attrs["local_start"], attrs["timezone"]),
             {:ok, finish} <- Welcome.local_time(attrs["local_end"], attrs["timezone"]) do
          input =
            attrs
            |> Map.drop(["local_start", "local_end"])
            |> Map.merge(%{"starts_at" => start, "ends_at" => finish})

          if a.record,
            do:
              Welcome.update(
                a.current_scope,
                a.group_id,
                a.record.id,
                input,
                a.record.revision,
                a.key
              ),
            else: Welcome.create(a.current_scope, a.group_id, input, a.key)
        end

      case result do
        {:ok, session} ->
          {:noreply, push_patch(socket, to: session_path(session.id, a.group_id, a.locale))}

        {:error, reason} ->
          {:noreply, assign(socket, form: to_form(attrs, as: "session"), error: message(reason))}
      end
    end
  end

  def handle_event("select-participants", params, socket) do
    a = socket.assigns

    result =
      Welcome.select(
        a.current_scope,
        a.group_id,
        a.record.id,
        Map.get(params, "people", []),
        a.record.revision,
        a.key
      )

    finish(socket, result)
  end

  def handle_event("prepare-drafts", _, socket) do
    a = socket.assigns

    ids =
      for p <- a.record.participants,
          p.invitation_state == "selected" and is_nil(p.draft_batch_id),
          do: p.user_id

    finish(
      socket,
      Welcome.prepare_drafts(
        a.current_scope,
        a.group_id,
        a.record.id,
        ids,
        a.record.revision,
        a.key
      )
    )
  end

  def handle_event("record-invited", %{"id" => id, "revision" => revision}, socket) do
    a = socket.assigns

    finish(
      socket,
      Welcome.record_invited(
        a.current_scope,
        a.group_id,
        a.record.id,
        id,
        integer(revision),
        a.key
      )
    )
  end

  def handle_event("outcome", %{"person" => attrs}, socket) do
    a = socket.assigns

    finish(
      socket,
      Welcome.record_outcome(
        a.current_scope,
        a.group_id,
        a.record.id,
        attrs["id"],
        attrs,
        integer(attrs["revision"]),
        a.key
      )
    )
  end

  def handle_event("move", %{"move" => attrs}, socket) do
    a = socket.assigns

    finish(
      socket,
      Welcome.move(
        a.current_scope,
        a.group_id,
        attrs["id"],
        attrs["target"],
        integer(attrs["revision"]),
        a.key
      )
    )
  end

  def handle_info(:refresh_access, socket) do
    a = socket.assigns

    case Welcome.list(a.current_scope, a.group_id) do
      {:ok, sessions} ->
        Process.send_after(self(), :refresh_access, 30_000)
        {:noreply, assign(socket, sessions: sessions)}

      _ ->
        {:noreply, denied(socket)}
    end
  end

  defp finish(socket, {:ok, _}) do
    a = socket.assigns

    {:noreply,
     socket
     |> put_flash(:info, gettext("Saved"))
     |> push_patch(to: session_path(a.record.id, a.group_id, a.locale))}
  end

  defp finish(socket, {:error, reason}) when reason in [:unauthorized, :not_found],
    do: {:noreply, denied(socket)}

  defp finish(socket, {:error, reason}), do: {:noreply, assign(socket, error: message(reason))}

  defp denied(socket),
    do:
      socket
      |> assign(record: nil, sessions: [], candidates: %{included: [], excluded: []}, events: [])
      |> put_flash(:error, gettext("This welcome session is unavailable."))
      |> redirect(to: ~p"/dashboard")

  defp list_path(group, locale), do: ~p"/manage/welcome-calls?#{%{group: group, locale: locale}}"

  defp session_path(id, group, locale),
    do: ~p"/manage/welcome-calls/#{id}?#{%{group: group, locale: locale}}"

  defp form_ref(a), do: a.group_id <> "-" <> ((a.record && a.record.id) || a.key)

  defp integer(value) do
    case Integer.parse(value || "") do
      {n, ""} -> n
      _ -> -1
    end
  end

  defp defaults(hosts, locale),
    do: %{
      "title" => "",
      "host_id" => List.first(hosts) && List.first(hosts).id,
      "language" => locale,
      "timezone" => "America/Toronto",
      "local_start" => "",
      "local_end" => "",
      "meeting_url" => "",
      "status" => "scheduled"
    }

  defp values(s),
    do: %{
      "title" => s.title,
      "host_id" => s.host_id,
      "language" => s.language,
      "timezone" => s.timezone,
      "local_start" => local_value(s.starts_at, s.timezone),
      "local_end" => local_value(s.ends_at, s.timezone),
      "meeting_url" => s.meeting_url,
      "status" => s.status
    }

  defp local_value(time, zone),
    do:
      Welcome.display_time(time, zone) |> String.split(" · ") |> hd() |> String.replace(" ", "T")

  defp person(user), do: if(user.name in [nil, ""], do: user.email, else: user.name)
  defp event_action("create"), do: gettext("Created")
  defp event_action("update"), do: gettext("Updated")
  defp event_action("select"), do: gettext("People selected")
  defp event_action("prepare_drafts"), do: gettext("Invitation drafts prepared")
  defp event_action("invitation_recorded"), do: gettext("Invitation recorded")
  defp event_action("rsvp"), do: gettext("Reply recorded")
  defp event_action("outcome_recorded"), do: gettext("Outcome recorded")
  defp event_action("moved"), do: gettext("Moved to another call")
  defp event_action(_), do: gettext("Updated")

  defp state("selected"), do: gettext("Selected")
  defp state("invited"), do: gettext("Invitation recorded")
  defp state("moved"), do: gettext("Moved to another call")
  defp state("withdrawn"), do: gettext("Withdrawn")
  defp state("pending"), do: gettext("Pending")
  defp state("accepted"), do: gettext("Accepted")
  defp state("declined"), do: gettext("Declined")
  defp state("unknown"), do: gettext("Not recorded")
  defp state("attended"), do: gettext("Attended")
  defp state("no_show"), do: gettext("Did not attend")
  defp state("completed"), do: gettext("Completed")
  defp state("scheduled"), do: gettext("Scheduled")
  defp state("cancelled"), do: gettext("Cancelled")
  defp state(_), do: gettext("Unknown")

  defp message(:conflict),
    do:
      gettext(
        "This record changed. Your draft is retained; reload the current session before saving."
      )

  defp message(:clock_change),
    do: gettext("This local time falls in a clock change. Choose an unambiguous time.")

  defp message(:invalid_time),
    do:
      gettext("Enter valid local start/end times and an IANA time zone, such as America/Toronto.")

  defp message(:cohort_size), do: gettext("Select one to five people for this first cohort.")

  defp message(:already_scheduled),
    do:
      gettext(
        "This person already has an upcoming welcome call. Move their existing selection instead."
      )

  defp message(:prepared_drafts_exist),
    do:
      gettext(
        "Invitation drafts already exist. Create a replacement session and move participants before preparing new drafts."
      )

  defp message(:not_started),
    do: gettext("Attendance can be recorded only after the call starts.")

  defp message(:not_finished), do: gettext("Record a no-show only after the call ends.")

  defp message(_),
    do: gettext("Check the session, current eligibility and permissions. Nothing was sent.")

  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="welcome"
      translated_path={list_path(@group_id, if(@locale == "fr", do: "en", else: "fr"))}
    >
      <section id="welcome-workspace" class="mx-auto max-w-6xl px-5 py-8 space-y-6">
        <header class="rounded-xl border border-base-300 bg-base-200 p-4 space-y-3">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <h1 class="text-3xl font-bold">{gettext("Welcome calls")}</h1>
            <.link
              patch={~p"/manage/welcome-calls/new?#{%{group: @group_id, locale: @locale}}"}
              class="btn btn-primary"
            >{gettext("Add welcome call")}</.link>
          </div>
          <form id="welcome-group-form" phx-change="group" phx-submit="group">
            <.input
              type="select"
              name="group"
              value={@group_id}
              label={gettext("Group")}
              options={Enum.map(@groups, &{&1.name, &1.id})}
            />
          </form>
        </header>
        <p :if={@error} role="alert" class="rounded border border-warning p-3">{@error}</p>
        <%= if @editing do %>
          <div
            id="welcome-editor"
            data-session-id={@record && @record.id}
            data-revision={@record && @record.revision}
            class="rounded-xl border border-base-300 p-4"
          >
            <h2 class="text-xl font-semibold">
              {if @record, do: gettext("Edit welcome call"), else: gettext("Add welcome call")}
            </h2>
            <div id={"welcome-form-container-" <> form_ref(assigns)}>
              <.form
                for={@form}
                id={"welcome-form-" <> form_ref(assigns)}
                data-welcome-form="true"
                phx-submit="save-session"
                class="space-y-3"
              >
                <input type="hidden" name="_welcome_ref" value={form_ref(assigns)} />
                <.input
                  field={@form[:title]}
                  id={"welcome-" <> form_ref(assigns) <> "-title"}
                  label={gettext("Title")}
                  required
                />
                <div class="grid sm:grid-cols-2 gap-3">
                  <.input
                    field={@form[:host_id]}
                    id={"welcome-" <> form_ref(assigns) <> "-host_id"}
                    type="select"
                    label={gettext("Host")}
                    options={Enum.map(@hosts, &{person(&1), &1.id})}
                    required
                  />
                  <.input
                    field={@form[:language]}
                    id={"welcome-" <> form_ref(assigns) <> "-language"}
                    type="select"
                    label={gettext("Session language")}
                    options={[{gettext("English"), "en"}, {gettext("French"), "fr"}]}
                  />
                  <.input
                    field={@form[:local_start]}
                    id={"welcome-" <> form_ref(assigns) <> "-local_start"}
                    type="datetime-local"
                    label={gettext("Local start time")}
                    required
                  />
                  <.input
                    field={@form[:local_end]}
                    id={"welcome-" <> form_ref(assigns) <> "-local_end"}
                    type="datetime-local"
                    label={gettext("Local end time")}
                    required
                  />
                </div>
                <.input
                  field={@form[:timezone]}
                  id={"welcome-" <> form_ref(assigns) <> "-timezone"}
                  label={gettext("Time zone")}
                  required
                />
                <p class="text-sm">
                  {gettext("Use an IANA time zone, for example America/Toronto or America/Vancouver.")}
                </p>
                <.input
                  field={@form[:meeting_url]}
                  id={"welcome-" <> form_ref(assigns) <> "-meeting_url"}
                  type="url"
                  label={gettext("HTTPS meeting link")}
                  required
                />
                <.input
                  :if={@record}
                  field={@form[:status]}
                  id={"welcome-" <> form_ref(assigns) <> "-status"}
                  type="select"
                  label={gettext("Status")}
                  options={Enum.map(~w(scheduled completed cancelled), &{state(&1), &1})}
                />
                <button class="btn btn-primary" phx-disable-with={gettext("Saving…")}>{gettext("Save")}</button>
                <.link patch={list_path(@group_id, @locale)} class="btn btn-outline">{gettext(
                  "Back to welcome calls"
                )}</.link>
              </.form>
            </div>
          </div>
          <%= if @record do %>
            <section id="welcome-cohort" class="space-y-4">
              <h2 class="text-2xl font-semibold">{gettext("Selected people")}</h2>
              <p>
                {gettext(
                  "Choose up to five eligible accounts. Selection does not send an invitation, subscribe anyone or grant membership."
                )}
              </p>
              <.form
                for={%{}}
                id="welcome-select"
                phx-submit="select-participants"
                class="rounded border p-4"
              >
                <label :for={user <- @candidates.included} class="flex gap-3 py-2"><input
                  type="checkbox"
                  name="people[]"
                  value={user.id}
                />{person(user)}</label>
                <p :if={@candidates.included == []}>
                  {gettext("No eligible accounts in this group.")}
                </p>
                <p :for={entry <- @candidates.excluded} class="text-sm">
                  {person(entry.user)} · {gettext(
                    "Excluded: welcome withdrawal or contact suppression."
                  )}
                </p>
                <button class="btn btn-outline">{gettext("Add selected people")}</button>
              </.form>
              <p>
                {gettext(
                  "Prepare private drafts, review them in Emails, and share invitations yourself. Record an invitation only after sharing it. No message or calendar booking is automatic."
                )}
              </p>
              <button phx-click="prepare-drafts" class="btn btn-primary">{gettext(
                "Prepare invitation drafts"
              )}</button>
              <article
                :for={p <- @record.participants}
                id={"welcome-person-" <> p.id}
                class="rounded-xl border border-base-300 p-4 space-y-3"
              >
                <h3 class="font-semibold">{person(p.user)}</h3>
                <dl class="grid sm:grid-cols-4 gap-3">
                  <div>
                    <dt>{gettext("Invitation")}</dt><dd>{state(p.invitation_state)}</dd>
                  </div>
                  <div>
                    <dt>{gettext("RSVP")}</dt><dd>{state(p.rsvp)}</dd>
                  </div>
                  <div>
                    <dt>{gettext("Attendance")}</dt><dd>{state(p.attendance)}</dd>
                  </div>
                  <div>
                    <dt>{gettext("Follow-up")}</dt><dd>{state(p.follow_up)}</dd>
                  </div>
                </dl>
                <.link
                  :if={p.draft_batch_id}
                  href={
                    ~p"/manage/mail/#{p.draft_batch_id}?#{%{locale: @locale, account_drafts: true}}"
                  }
                  class="underline"
                >{gettext("Open invitation drafts (author only)")}</.link>
                <button
                  :if={p.invitation_state == "selected"}
                  phx-click="record-invited"
                  phx-value-id={p.id}
                  phx-value-revision={p.revision}
                  class="btn btn-outline"
                >{gettext("Record invitation shared")}</button>
                <.form
                  for={%{}}
                  as={:person}
                  id={"welcome-outcome-" <> p.id}
                  phx-submit="outcome"
                  class="grid sm:grid-cols-3 gap-3"
                >
                  <input type="hidden" name="person[id]" value={p.id} /><input
                    type="hidden"
                    name="person[revision]"
                    value={p.revision}
                  />
                  <.input
                    type="select"
                    name="person[attendance]"
                    value={p.attendance}
                    label={gettext("Attendance")}
                    options={Enum.map(~w(unknown attended no_show), &{state(&1), &1})}
                  />
                  <.input
                    type="select"
                    name="person[follow_up]"
                    value={p.follow_up}
                    label={gettext("Follow-up")}
                    options={Enum.map(~w(pending completed), &{state(&1), &1})}
                  />
                  <.input
                    name="person[notes]"
                    value={p.notes}
                    label={gettext("Private follow-up notes")}
                  />
                  <button class="btn btn-outline">{gettext("Record outcome")}</button>
                </.form>
                <.form
                  :if={p.invitation_state in ["selected", "invited"]}
                  for={%{}}
                  as={:move}
                  id={"welcome-move-" <> p.id}
                  phx-submit="move"
                  class="flex flex-wrap gap-3 items-end"
                >
                  <input type="hidden" name="move[id]" value={p.id} /><input
                    type="hidden"
                    name="move[revision]"
                    value={p.revision}
                  />
                  <.input
                    type="select"
                    name="move[target]"
                    value=""
                    label={gettext("Another welcome call")}
                    prompt={gettext("Choose a call")}
                    options={
                      for s <- @sessions,
                          s.id != @record.id and s.status == "scheduled",
                          do: {s.title, s.id}
                    }
                  />
                  <button class="btn btn-outline">{gettext("Move selection")}</button>
                </.form>
              </article>
            </section>
            <details class="rounded border p-4">
              <summary>{gettext("History")}</summary><p
                :for={event <- @events}
                id={"welcome-event-" <> event.id}
                class="text-sm break-all"
              >
                {event_action(event.action)} · {Calendar.strftime(
                  event.inserted_at,
                  "%Y-%m-%d %H:%M UTC"
                )} · {gettext("Actor")}: {event.actor_id}
              </p>
            </details>
          <% end %>
        <% else %>
          <div id="welcome-list" class="space-y-3">
            <p :if={@sessions == []}>{gettext("No welcome calls yet.")}</p>
            <article :for={session <- @sessions} class="rounded border p-4">
              <.link
                patch={session_path(session.id, @group_id, @locale)}
                class="font-semibold underline"
              >{session.title}</.link><p>
                {Welcome.display_time(session.starts_at, session.timezone)} · {if(
                  session.language == "fr",
                  do: gettext("French"),
                  else: gettext("English")
                )} · {state(session.status)}
              </p>
            </article>
          </div>
        <% end %>
      </section>
    </Layouts.management>
    """
  end
end
