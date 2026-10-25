defmodule PauseAiCa.Tasks do
  @moduledoc "Organizer tasks with current group authority and canonical attributed events."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.{Scope, User}
  alias PauseAiCa.Tasks.{Dependency, Event, Task}
  alias PauseAiCa.Volunteers.{Group, Manager}

  @task_fields ~w(id title description requester_id accountable_id assignee_id backup_id due_date status revision source prerequisite_ids)a
  @editable ~w(title description accountable_id assignee_id backup_id due_date status prerequisite_ids reason)

  def groups(scope), do: Volunteers.groups(scope)

  def members(scope, group_id) do
    with :ok <- authorize(scope, group_id), do: {:ok, eligible_members(group_id)}
  end

  def list(scope, group_id) do
    with :ok <- authorize(scope, group_id), do: {:ok, load_tasks(group_id)}
  end

  def get(scope, group_id, id) do
    with :ok <- authorize(scope, group_id),
         true <- uuid?(id),
         %Task{} = task <-
           Repo.one(from t in Task, where: t.group_id == ^group_id and t.id == ^id) do
      {:ok, attach_prerequisites(task)}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def activity(scope, group_id, task_id \\ nil) do
    with :ok <- authorize(scope, group_id),
         true <- is_nil(task_id) or uuid?(task_id) do
      query =
        from e in Event,
          where: e.group_id == ^group_id,
          order_by: [desc: e.inserted_at, desc: e.id]

      query = if task_id, do: from(e in query, where: e.task_id == ^task_id), else: query
      {:ok, Repo.all(query)}
    else
      {:error, _} = error -> error
      _ -> {:error, :not_found}
    end
  end

  def create(scope, group_id, attrs, command_id),
    do: mutate(scope, group_id, :create, nil, attrs, nil, command_id)

  def update(scope, group_id, id, attrs, revision, command_id),
    do: mutate(scope, group_id, :update, id, attrs, revision, command_id)

  defp mutate(scope, group_id, action, id, attrs, revision, command_id) do
    with :ok <- authorize(scope, group_id),
         {:ok, command} <-
           PhoenixTasks.Command.new(%{
             action: action,
             task_id: id,
             expected_revision: revision,
             command_key: command_id,
             attrs: command_attrs(attrs)
           }) do
      Repo.transaction(fn ->
        # All task commands in one group serialize here, including opposite DAG links.
        group = Repo.one(from g in Group, where: g.id == ^group_id, lock: "FOR UPDATE")
        if is_nil(group), do: Repo.rollback(:unauthorized)
        if authorize(scope, group_id) != :ok, do: Repo.rollback(:unauthorized)

        tasks = load_tasks(group_id)

        prior =
          Repo.one(
            from e in Event,
              where:
                e.group_id == ^group_id and e.actor_id == ^scope.user.id and
                  e.command_id == ^command_id
          )

        context = %{
          scope_id: group_id,
          actor_id: scope.user.id,
          eligible_person_ids: Enum.map(eligible_members(group_id), & &1.id),
          tasks: Enum.map(tasks, &to_core/1),
          task_id: Ecto.UUID.generate(),
          event_id: Ecto.UUID.generate(),
          at: DateTime.utc_now(),
          replay: replay(prior)
        }

        case PhoenixTasks.plan(command, context) do
          {:ok, %{replay?: true, task: task}} -> from_core(task, group_id)
          {:ok, plan} -> persist(plan, group_id, scope.user.id, command_id, tasks)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  defp persist(plan, group_id, actor_id, command_id, tasks) do
    core = plan.task

    current =
      Enum.find(tasks, &(&1.id == core.id)) ||
        %Task{id: core.id, group_id: group_id, requester_id: core.requester_id}

    attrs = Map.take(core, @task_fields)

    changeset =
      Task.changeset(current, attrs)
      |> Ecto.Changeset.put_change(:revision, core.revision)

    task =
      case Repo.insert_or_update(changeset) do
        {:ok, task} -> task
        {:error, _} -> Repo.rollback({:validation, %{task: :invalid}})
      end

    Repo.delete_all(
      from d in Dependency, where: d.group_id == ^group_id and d.task_id == ^task.id
    )

    Enum.each(core.prerequisite_ids, fn prerequisite_id ->
      Repo.insert!(%Dependency{
        group_id: group_id,
        task_id: task.id,
        prerequisite_id: prerequisite_id
      })
    end)

    event = plan.event

    Repo.insert!(%Event{
      id: event.id,
      group_id: group_id,
      task_id: task.id,
      actor_id: actor_id,
      command_id: command_id,
      fingerprint: plan.fingerprint,
      action: to_string(event.action),
      revision: task.revision,
      details: Map.drop(event, [:id, :task_id, :scope_id, :actor_id]),
      result: json_map(%{task: core, event: event})
    })

    %{task | prerequisite_ids: core.prerequisite_ids}
  end

  defp replay(nil), do: nil

  defp replay(event) do
    %{
      task: core_from_json(event.result["task"]),
      event: event_from_json(event.result["event"]),
      fingerprint: event.fingerprint,
      replay?: false
    }
  end

  defp to_core(task), do: task |> Map.take(@task_fields) |> Map.put(:scope_id, task.group_id)

  defp core_from_json(map) do
    core = Map.new(@task_fields ++ [:scope_id], fn key -> {key, map[Atom.to_string(key)]} end)

    if is_binary(core.due_date),
      do: %{core | due_date: Date.from_iso8601!(core.due_date)},
      else: core
  end

  defp from_core(core, group_id),
    do: struct(Task, core |> Map.take(@task_fields) |> Map.put(:group_id, group_id))

  defp json_map(map), do: map |> Jason.encode!() |> Jason.decode!()

  defp event_from_json(map) do
    fields =
      ~w(id task_id scope_id actor_id action command_key expected_revision resulting_revision at reason changes)a

    Map.new(fields, fn key -> {key, map[Atom.to_string(key)]} end)
  end

  defp command_attrs(attrs) do
    permitted_attrs(attrs)
    |> Map.new(fn {key, value} ->
      if key in ~w(accountable_id assignee_id backup_id) and value == "",
        do: {key, nil},
        else: {key, value}
    end)
  end

  defp permitted_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end) |> Map.take(@editable)
  end

  defp permitted_attrs(_), do: %{}

  defp authorize(%Scope{} = scope, group_id) do
    if uuid?(group_id) and Enum.any?(groups(scope), &(&1.id == group_id)),
      do: :ok,
      else: {:error, :unauthorized}
  end

  defp authorize(_, _), do: {:error, :unauthorized}
  defp uuid?(id), do: match?({:ok, _}, Ecto.UUID.cast(id))

  defp eligible_members(group_id) do
    Repo.all(
      from u in User,
        join: m in Manager,
        on: m.user_id == u.id,
        where: m.group_id == ^group_id and not is_nil(u.confirmed_at),
        order_by: [asc: u.email],
        distinct: true
    )
  end

  defp load_tasks(group_id) do
    prerequisites =
      Repo.all(
        from d in Dependency,
          where: d.group_id == ^group_id,
          order_by: d.prerequisite_id
      )
      |> Enum.group_by(& &1.task_id, & &1.prerequisite_id)

    Repo.all(
      from t in Task,
        where: t.group_id == ^group_id,
        order_by: [asc: t.inserted_at, asc: t.id]
    )
    |> Enum.map(&%{&1 | prerequisite_ids: Map.get(prerequisites, &1.id, [])})
  end

  defp attach_prerequisites(task) do
    ids =
      Repo.all(
        from d in Dependency,
          where: d.group_id == ^task.group_id and d.task_id == ^task.id,
          order_by: d.prerequisite_id,
          select: d.prerequisite_id
      )

    %{task | prerequisite_ids: ids}
  end
end
