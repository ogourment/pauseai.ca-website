defmodule PauseAiCaWeb.TasksLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{Tasks, Incubators}

  @impl true
  def mount(params, _, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    if Application.get_env(:pauseai_ca, :tasks_enabled, false) do
      if connected?(socket), do: Process.send_after(self(), :refresh_access, 30_000)

      {:ok,
       assign(socket,
         locale: locale,
         page_title: gettext("Tasks"),
         groups: [],
         admin_nonmember: false,
         group_id: nil,
         members: [],
         tasks: [],
         events: [],
         record: nil,
         editing: false,
         view: "tasks",
         form: to_form(%{}, as: "task"),
         command_id: Ecto.UUID.generate(),
         error: nil,
         field_errors: %{},
         blocked: [],
         conflict: false
       )}
    else
      {:ok, redirect(socket, to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_params(params, _, socket) do
    scope = socket.assigns.current_scope
    groups = Tasks.groups(scope)
    group_id = params["group"] || (List.first(groups) && List.first(groups).id)

    if groups == [] and is_nil(params["group"]) and socket.assigns.live_action == :index do
      {:noreply,
       assign(socket,
         groups: [],
         group_id: nil,
         tasks: [],
         members: [],
         events: [],
         record: nil,
         editing: false
       )}
    else
      with true <- Enum.any?(groups, &(&1.id == group_id)),
           {:ok, tasks} <- Tasks.list(scope, group_id),
           {:ok, members} <- Tasks.members(scope, group_id),
           {:ok, events} <- Tasks.activity(scope, group_id),
           {:ok, record} <- record(scope, group_id, params["id"]) do
        values =
          if record,
            do: values(record),
            else:
              defaults(
                if(Enum.any?(members, &(&1.id == scope.user.id)), do: scope.user.id, else: "")
              )

        {:noreply,
         assign(socket,
           page_title:
             cond do
               record -> record.title
               socket.assigns.live_action == :new -> gettext("Add task")
               params["view"] == "activity" -> gettext("Activity")
               true -> gettext("Tasks")
             end,
           groups: groups,
           admin_nonmember: Incubators.superadmin_nonmember?(scope, group_id),
           group_id: group_id,
           tasks: tasks,
           members: members,
           events: events,
           record: record,
           editing: socket.assigns.live_action in [:new, :show],
           view: if(params["view"] == "activity", do: "activity", else: "tasks"),
           form: to_form(values, as: "task"),
           command_id: Ecto.UUID.generate(),
           error: nil,
           field_errors: %{},
           blocked: [],
           conflict: false
         )}
      else
        _ -> {:noreply, unavailable(socket)}
      end
    end
  end

  defp record(_, _, nil), do: {:ok, nil}
  defp record(scope, group_id, id), do: Tasks.get(scope, group_id, id)

  @impl true
  def handle_event("group", %{"group" => group}, socket) do
    {:noreply, push_patch(socket, to: list_path(group, socket.assigns.locale))}
  end

  def handle_event(event, %{"_task_ref" => ref} = params, socket)
      when event in ["validate", "save"] do
    if ref == form_ref(socket.assigns) do
      handle_task_event(event, params, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event(event, _, socket) when event in ["validate", "save"], do: {:noreply, socket}

  def handle_event("reload", _, socket) do
    a = socket.assigns

    case Tasks.get(a.current_scope, a.group_id, a.record.id) do
      {:ok, record} ->
        {:noreply,
         assign(socket,
           record: record,
           form: to_form(values(record), as: "task"),
           command_id: Ecto.UUID.generate(),
           error: nil,
           conflict: false,
           field_errors: %{},
           blocked: []
         )}

      _ ->
        {:noreply, unavailable(socket)}
    end
  end

  def handle_event("reapply", _, socket) do
    a = socket.assigns

    case Tasks.get(a.current_scope, a.group_id, a.record.id) do
      {:ok, record} ->
        {:noreply,
         assign(socket,
           record: record,
           command_id: Ecto.UUID.generate(),
           field_errors: %{},
           blocked: [],
           conflict: false,
           error:
             gettext("Your draft is retained. Review it, then save against the current revision.")
         )}

      _ ->
        {:noreply, unavailable(socket)}
    end
  end

  defp handle_task_event("validate", %{"task" => attrs}, socket) do
    case Tasks.list(socket.assigns.current_scope, socket.assigns.group_id) do
      {:ok, _} -> {:noreply, assign(socket, form: to_form(attrs, as: "task"), error: nil)}
      _ -> {:noreply, unavailable(socket)}
    end
  end

  defp handle_task_event("save", %{"task" => attrs}, socket) do
    a = socket.assigns
    attrs = Map.put_new(attrs, "prerequisite_ids", [])

    result =
      if a.record do
        Tasks.update(
          a.current_scope,
          a.group_id,
          a.record.id,
          attrs,
          a.record.revision,
          a.command_id
        )
      else
        Tasks.create(a.current_scope, a.group_id, attrs, a.command_id)
      end

    case result do
      {:ok, task} ->
        {:noreply,
         socket
         |> push_patch(to: task_path(task.id, a.group_id, a.locale))}

      {:error, reason} when reason in [:unauthorized, :not_found] ->
        {:noreply, unavailable(socket)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           form: to_form(attrs, as: "task"),
           error: error_text(reason),
           field_errors: validation_errors(reason),
           blocked: blockers(reason),
           conflict: reason in [:conflict, :stale_revision]
         )}
    end
  end

  @impl true
  def handle_info(:refresh_access, %{assigns: %{group_id: nil}} = socket) do
    Process.send_after(self(), :refresh_access, 30_000)

    case Tasks.groups(socket.assigns.current_scope) do
      [] ->
        {:noreply, socket}

      [group | _] ->
        {:noreply, push_patch(socket, to: list_path(group.id, socket.assigns.locale))}
    end
  end

  def handle_info(:refresh_access, socket) do
    a = socket.assigns

    with {:ok, tasks} <- Tasks.list(a.current_scope, a.group_id),
         {:ok, events} <- Tasks.activity(a.current_scope, a.group_id),
         {:ok, members} <- Tasks.members(a.current_scope, a.group_id) do
      Process.send_after(self(), :refresh_access, 30_000)

      {:noreply,
       assign(socket,
         tasks: tasks,
         events: events,
         members: members,
         admin_nonmember: Incubators.superadmin_nonmember?(a.current_scope, a.group_id)
       )}
    else
      _ -> {:noreply, unavailable(socket)}
    end
  end

  defp unavailable(socket) do
    socket
    |> assign(tasks: [], events: [], members: [], record: nil, form: to_form(%{}, as: "task"))
    |> put_flash(:error, gettext("This group or task is unavailable."))
    |> redirect(to: ~p"/dashboard")
  end

  defp form_ref(assigns),
    do: assigns.group_id <> "-" <> ((assigns.record && assigns.record.id) || assigns.command_id)

  defp defaults(actor) do
    %{
      "title" => "",
      "description" => "",
      "accountable_id" => actor,
      "assignee_id" => "",
      "backup_id" => "",
      "due_date" => "",
      "status" => "open",
      "prerequisite_ids" => [],
      "reason" => ""
    }
  end

  defp values(task) do
    Map.new(
      ~w(title description accountable_id assignee_id backup_id due_date status prerequisite_ids)a,
      fn key -> {Atom.to_string(key), Map.get(task, key)} end
    )
    |> Map.put("reason", "")
  end

  defp list_path(group, locale, view \\ "tasks"),
    do: ~p"/manage/tasks?#{%{group: group, locale: locale, view: view}}"

  defp task_path(id, group, locale),
    do: ~p"/manage/tasks/#{id}?#{%{group: group, locale: locale}}"

  defp person(id, members) do
    case Enum.find(members, &(&1.id == id)) do
      nil -> if(id, do: gettext("Recorded account %{id}", id: id), else: gettext("Unassigned"))
      user -> user.name || user.email
    end
  end

  defp assignment_options(members, current) do
    options = Enum.map(members, &{&1.name || &1.email, &1.id})

    if current not in [nil, ""] and not Enum.any?(members, &(&1.id == current)),
      do: [{gettext("Former group manager"), current} | options],
      else: options
  end

  defp status("open"), do: gettext("Open")
  defp status("in_progress"), do: gettext("In progress")
  defp status("in_review"), do: gettext("In review")
  defp status("done"), do: gettext("Done")
  defp status("cancelled"), do: gettext("Cancelled")
  defp status(_), do: gettext("Unknown")
  defp action("created"), do: gettext("Created")
  defp action("updated"), do: gettext("Updated")
  defp action("delegated"), do: gettext("Reassigned")
  defp action("transitioned"), do: gettext("Status changed")
  defp action(_), do: gettext("Changed")

  defp event_changes(event) do
    event.details
    |> Map.get("changes", %{})
    |> Enum.filter(fn {field, _} ->
      field in ~w(title status accountable_id assignee_id backup_id due_date)
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp field_label("title"), do: gettext("Title")
  defp field_label("status"), do: gettext("Status")
  defp field_label("accountable_id"), do: gettext("Accountable owner")
  defp field_label("assignee_id"), do: gettext("Assigned to")
  defp field_label("backup_id"), do: gettext("Backup")
  defp field_label("due_date"), do: gettext("Due date")

  defp change_value(field, value, members)
       when field in ["accountable_id", "assignee_id", "backup_id"], do: person(value, members)

  defp change_value("status", value, _) when is_binary(value), do: status(value)
  defp change_value(_, nil, _), do: "—"
  defp change_value(_, value, _), do: to_string(value)

  defp error_text(reason) when reason in [:conflict, :stale_revision],
    do: gettext("This task changed in another tab. Your draft has been retained.")

  defp error_text(:command_conflict),
    do: gettext("This save key was already used. Reload the task before saving again.")

  defp error_text({:blocked, tasks}),
    do:
      gettext("Complete these prerequisites first: %{titles}",
        titles: Enum.map_join(tasks, ", ", & &1.title)
      )

  defp error_text({:validation, _}), do: gettext("Please correct the highlighted fields.")

  defp error_text(_),
    do:
      gettext(
        "Check the title, date, assignments, reassignment reason and prerequisites. Your draft has been retained."
      )

  defp validation_errors({:validation, errors}),
    do: Map.new(errors, fn {field, reason} -> {field, [validation_message(reason)]} end)

  defp validation_errors(_), do: %{}
  defp blockers({:blocked, tasks}), do: tasks
  defp blockers(_), do: []

  defp validation_message(:must_differ),
    do: gettext("Choose a different person from the assignee.")

  defp validation_message(:ineligible),
    do: gettext("Choose a current confirmed manager of this group.")

  defp validation_message(:required), do: gettext("This field is required.")
  defp validation_message(:cycle), do: gettext("These prerequisites would create a cycle.")

  defp validation_message(:unavailable),
    do: gettext("A prerequisite is unavailable in this group.")

  defp validation_message(:invalid_transition),
    do: gettext("Reopen a completed or cancelled task before changing its status.")

  defp validation_message(_), do: gettext("Check this value.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.management
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      active_tab="tasks"
      translated_path={list_path(@group_id, if(@locale == "fr", do: "en", else: "fr"))}
    >
      <section class="mx-auto max-w-6xl px-5 py-6" id="tasks-workspace">
        <div class="rounded-xl border border-base-300 bg-base-200 p-4 space-y-3">
          <div class="flex flex-wrap justify-between items-center gap-3">
            <h1 class="text-2xl font-bold">{gettext("Tasks")}</h1>
            <.link
              :if={@group_id}
              patch={~p"/manage/tasks/new?#{%{group: @group_id, locale: @locale}}"}
              class="btn btn-primary"
            >{gettext("Add task")}</.link>
          </div>
          <p :if={@admin_nonmember} id="task-superadmin-access-note" class="text-sm text-stone-600">
            {gettext("You have full access as a superadmin. You are not a member of this group.")}
          </p>
          <form :if={@group_id} phx-change="group" phx-submit="group" id="task-group-form">
            <.input
              type="select"
              name="group"
              label={gettext("Group")}
              value={@group_id}
              options={Enum.map(@groups, &{&1.name, &1.id})}
            />
          </form>
          <nav :if={@group_id} class="flex gap-4" aria-label={gettext("Task views")}>
            <.link
              patch={list_path(@group_id, @locale)}
              aria-current={if @view == "tasks", do: "page"}
              class="underline"
            >{gettext("Tasks")}</.link>
            <.link
              patch={list_path(@group_id, @locale, "activity")}
              aria-current={if @view == "activity", do: "page"}
              class="underline"
            >{gettext("Activity")}</.link>
          </nav>
        </div>
        <div :if={is_nil(@group_id)} id="tasks-no-groups" class="mt-6 space-y-3">
          <h2 class="text-xl font-semibold">{gettext("No organizer groups yet")}</h2>
          <p>
            {gettext(
              "Tasks belong to organizer groups. Create a group and assign its managers to start organizing tasks."
            )}
          </p>
          <.link
            :if={PauseAiCa.Volunteers.superadmin?(@current_scope)}
            navigate={~p"/volunteer-signups?#{%{locale: @locale}}" <> "#group-management"}
            class="underline"
          >{gettext("Manage groups and managers")}</.link>
        </div>
        <div
          :if={@editing}
          class="mt-6 rounded-xl border border-base-300 p-4"
          id="task-editor"
          data-task-id={@record && @record.id}
          data-revision={@record && @record.revision}
          data-status={@record && @record.status}
        >
          <h2 class="text-xl font-semibold">
            {if @record, do: gettext("Edit task"), else: gettext("Add task")}
          </h2>
          <p :if={@record} class="text-sm my-2 break-all">
            {gettext("Task ID")}: {@record.id} · {gettext("Revision")}: {@record.revision}
          </p>
          <div :if={@error} role="alert" class="my-3 rounded border border-warning p-3">{@error}</div>
          <ul :if={@blocked != []} class="my-3 list-disc pl-5">
            <li :for={task <- @blocked}>
              <.link patch={task_path(task.id, @group_id, @locale)} class="underline">{task.title}</.link>
            </li>
          </ul>
          <p :if={@record} class="my-2 text-sm">
            {gettext("Requested by")}: {person(@record.requester_id, @members)}
          </p>
          <div :if={@conflict} class="flex flex-wrap gap-3 mb-3">
            <button phx-click="reload" class="btn btn-outline">{gettext("Reload current values")}</button>
            <button phx-click="reapply" class="btn btn-outline">{gettext("Keep my draft for review")}</button>
          </div>
          <div id={"task-form-container-" <> ((@record && @record.id) || @command_id)}>
            <.form
              for={@form}
              id={"task-form-" <> form_ref(assigns)}
              data-task-form="true"
              phx-change="validate"
              phx-submit="save"
              class="space-y-3"
            >
              <input type="hidden" name="_task_ref" value={form_ref(assigns)} />
              <.input
                field={@form[:title]}
                id={"task-" <> form_ref(assigns) <> "-title"}
                errors={Map.get(@field_errors, :title, [])}
                label={gettext("Title")}
                required
                maxlength="200"
              />
              <div class="grid gap-3 sm:grid-cols-3">
                <.input
                  field={@form[:accountable_id]}
                  id={"task-" <> form_ref(assigns) <> "-accountable_id"}
                  errors={Map.get(@field_errors, :accountable_id, [])}
                  type="select"
                  label={gettext("Accountable owner")}
                  options={assignment_options(@members, @form[:accountable_id].value)}
                  prompt={gettext("Choose a manager")}
                />
                <.input
                  field={@form[:assignee_id]}
                  id={"task-" <> form_ref(assigns) <> "-assignee_id"}
                  errors={Map.get(@field_errors, :assignee_id, [])}
                  type="select"
                  label={gettext("Assigned to")}
                  options={assignment_options(@members, @form[:assignee_id].value)}
                  prompt={gettext("Unassigned")}
                />
                <.input
                  field={@form[:backup_id]}
                  id={"task-" <> form_ref(assigns) <> "-backup_id"}
                  errors={Map.get(@field_errors, :backup_id, [])}
                  type="select"
                  label={gettext("Backup")}
                  options={assignment_options(@members, @form[:backup_id].value)}
                  prompt={gettext("No backup")}
                />
              </div>
              <div class="grid gap-3 sm:grid-cols-2">
                <.input
                  field={@form[:due_date]}
                  id={"task-" <> form_ref(assigns) <> "-due_date"}
                  errors={Map.get(@field_errors, :due_date, [])}
                  type="date"
                  label={gettext("Due date")}
                />
                <.input
                  :if={@record}
                  field={@form[:status]}
                  id={"task-" <> form_ref(assigns) <> "-status"}
                  errors={Map.get(@field_errors, :status, [])}
                  type="select"
                  label={gettext("Status")}
                  options={Enum.map(~w(open in_progress in_review done cancelled), &{status(&1), &1})}
                />
              </div>
              <.input
                :if={@record}
                field={@form[:reason]}
                id={"task-" <> form_ref(assigns) <> "-reason"}
                errors={Map.get(@field_errors, :reason, [])}
                label={gettext("Reason for reassignment")}
              />
              <.input
                field={@form[:prerequisite_ids]}
                id={"task-" <> form_ref(assigns) <> "-prerequisite_ids"}
                errors={Map.get(@field_errors, :prerequisite_ids, [])}
                type="select"
                multiple
                label={gettext("Prerequisites")}
                options={
                  for task <- @tasks,
                      is_nil(@record) or task.id != @record.id,
                      do: {task.title, task.id}
                }
              />
              <details open={@form[:description].value not in [nil, ""]}>
                <summary class="cursor-pointer">{gettext("Description")}</summary>
                <.input
                  field={@form[:description]}
                  id={"task-" <> form_ref(assigns) <> "-description"}
                  errors={Map.get(@field_errors, :description, [])}
                  type="textarea"
                  label={gettext("Description")}
                  rows="4"
                />
              </details>
              <div class="flex flex-wrap gap-3">
                <button
                  type="submit"
                  class="btn btn-primary"
                  phx-disable-with={gettext("Saving…")}
                  disabled={@conflict}
                >{gettext("Save")}</button>
                <.link patch={list_path(@group_id, @locale)} class="btn btn-outline">{gettext(
                  "Back to tasks"
                )}</.link>
              </div>
            </.form>
          </div>
          <h3 :if={@record} class="mt-5 font-semibold">{gettext("Task history")}</h3>
          <.activity
            :if={@record}
            events={Enum.filter(@events, &(&1.task_id == @record.id))}
            members={@members}
            group_id={@group_id}
            locale={@locale}
          />
        </div>
        <div
          :if={not is_nil(@group_id) and !@editing and @view == "tasks"}
          class="mt-6 space-y-3"
          id="task-list"
        >
          <p :if={@tasks == []}>{gettext("No tasks yet. Add the first task for this group.")}</p>
          <article :for={task <- @tasks} class="rounded-xl border border-base-300 p-4">
            <.link patch={task_path(task.id, @group_id, @locale)} class="font-semibold underline">{task.title}</.link>
            <p class="text-sm mt-2">
              {status(task.status)} · {gettext("Assigned to")}: {person(task.assignee_id, @members)}
            </p>
            <p :if={task.due_date} class="text-sm">{gettext("Due date")}: {task.due_date}</p>
          </article>
        </div>
        <div :if={!@editing and @view == "activity"} class="mt-6" id="group-task-activity">
          <.activity events={@events} members={@members} group_id={@group_id} locale={@locale} />
        </div>
      </section>
    </Layouts.management>
    """
  end

  attr :events, :list, required: true
  attr :members, :list, required: true
  attr :group_id, :string, required: true
  attr :locale, :string, required: true

  defp activity(assigns) do
    ~H"""
    <div class="space-y-3">
      <p :if={@events == []}>{gettext("No task activity yet.")}</p>
      <article
        :for={event <- @events}
        id={"task-event-" <> event.id}
        class="rounded border border-base-300 p-3 text-sm"
      >
        <p>
          {person(event.actor_id, @members)} · {action(event.action)} ·
          <time>{Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC")}</time>
        </p>
        <.link patch={task_path(event.task_id, @group_id, @locale)} class="underline">{get_in(
          event.result,
          ["task", "title"]
        ) || gettext("Open task")}</.link>
        <dl class="mt-2">
          <div :for={{field, change} <- event_changes(event)}>
            <dt class="inline font-semibold">{field_label(field)}:</dt>
            <dd class="inline">
              {change_value(field, change["from"], @members)} → {change_value(
                field,
                change["to"],
                @members
              )}
            </dd>
          </div>
        </dl>
        <p :if={Map.get(event.details, "reason") not in [nil, ""]}>
          {Map.get(event.details, "reason")}
        </p>
        <p class="text-xs break-all">{gettext("Event ID")}: {event.id}</p>
      </article>
    </div>
    """
  end
end
