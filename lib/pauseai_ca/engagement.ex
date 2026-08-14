defmodule PauseAiCa.Engagement do
  @moduledoc """
  The Engagement context.
  """

  import Ecto.Query, warn: false
  alias PauseAiCa.Repo

  alias PauseAiCa.Engagement.{Action, LearningSignal}
  alias PauseAiCa.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any action changes.

  The broadcasted messages match the pattern:

    * {:created, %Action{}}
    * {:updated, %Action{}}
    * {:deleted, %Action{}}

  """
  def subscribe_actions(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(PauseAiCa.PubSub, "user:#{key}:actions")
  end

  defp broadcast_action(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(PauseAiCa.PubSub, "user:#{key}:actions", message)
  end

  @doc """
  Returns the list of actions.

  ## Examples

      iex> list_actions(scope)
      [%Action{}, ...]

  """
  def list_actions(%Scope{} = scope) do
    from(action in Action,
      where: action.user_id == ^scope.user.id,
      order_by: [desc: action.happened_on, desc: action.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single action.

  Raises `Ecto.NoResultsError` if the Action does not exist.

  ## Examples

      iex> get_action!(scope, 123)
      %Action{}

      iex> get_action!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_action!(%Scope{} = scope, id) do
    Repo.get_by!(Action, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a action.

  ## Examples

      iex> create_action(scope, %{field: value})
      {:ok, %Action{}}

      iex> create_action(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_action(%Scope{} = scope, attrs) do
    with {:ok, action = %Action{}} <-
           %Action{}
           |> Action.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_action(scope, {:created, action})
      {:ok, action}
    end
  end

  @doc """
  Marks an action as having actually happened.
  """
  def confirm_action(%Scope{} = scope, %Action{} = action) do
    true = action.user_id == scope.user.id

    with {:ok, action} <- action |> Action.confirm_changeset() |> Repo.update() do
      broadcast_action(scope, {:updated, action})
      {:ok, action}
    end
  end

  @doc """
  Actions the user has not yet told us actually happened.
  """
  def list_pending_actions(%Scope{} = scope) do
    Repo.all(
      from a in Action,
        where: a.user_id == ^scope.user.id and is_nil(a.confirmed_at),
        order_by: [desc: a.inserted_at]
    )
  end

  @doc """
  Updates a action.

  ## Examples

      iex> update_action(scope, action, %{field: new_value})
      {:ok, %Action{}}

      iex> update_action(scope, action, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_action(%Scope{} = scope, %Action{} = action, attrs) do
    true = action.user_id == scope.user.id

    with {:ok, action = %Action{}} <-
           action
           |> Action.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_action(scope, {:updated, action})
      {:ok, action}
    end
  end

  @doc """
  Deletes a action.

  ## Examples

      iex> delete_action(scope, action)
      {:ok, %Action{}}

      iex> delete_action(scope, action)
      {:error, %Ecto.Changeset{}}

  """
  def delete_action(%Scope{} = scope, %Action{} = action) do
    true = action.user_id == scope.user.id

    with {:ok, action = %Action{}} <-
           Repo.delete(action) do
      broadcast_action(scope, {:deleted, action})
      {:ok, action}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking action changes.

  ## Examples

      iex> change_action(scope, action)
      %Ecto.Changeset{data: %Action{}}

  """
  def change_action(%Scope{} = scope, %Action{} = action, attrs \\ %{}) do
    true = action.user_id == scope.user.id

    Action.changeset(action, attrs, scope)
  end

  def new_action(%Scope{} = scope) do
    %Action{user_id: scope.user.id, happened_on: Date.utc_today()}
  end

  @trend_days 14

  @doc "Record one anonymous visit in a daily aggregate."
  def record_visit(visited_on \\ Date.utc_today()) do
    Repo.insert!(
      %PauseAiCa.Engagement.DailyVisit{visited_on: visited_on, count: 1},
      on_conflict: [inc: [count: 1]],
      conflict_target: :visited_on
    )
  end

  @doc "Records a durable learning signal once per browser, kind, and subject."
  def record_learning_signal(visitor_id, user, kind, subject \\ "", value \\ nil) do
    attrs = %{
      visitor_id: visitor_id,
      user_id: user && user.id,
      kind: kind,
      subject: subject,
      value: value
    }

    %LearningSignal{}
    |> LearningSignal.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:user_id, :value, :updated_at]},
      conflict_target: [:visitor_id, :kind, :subject]
    )
  end

  @doc "Associates signals recorded in this browser before sign-in with its account."
  def associate_learning_visitor(visitor_id, user_id) do
    from(signal in LearningSignal, where: signal.visitor_id == ^visitor_id)
    |> Repo.update_all(set: [user_id: user_id])
  end

  @learning_kinds [
    {"question_answered", :question_answers},
    {"questionnaire_completed", :questionnaires_completed},
    {"learn_page_visited", :learn_page_visitors},
    {"resource_opened", :resources_opened},
    {"resource_bookmarked", :resources_bookmarked}
  ]

  @doc "Distinct people who produced each learning signal and across the whole learning funnel."
  def learning_metrics do
    identities_by_kind =
      Repo.all(
        from signal in LearningSignal, select: {signal.kind, signal.user_id, signal.visitor_id}
      )
      |> Enum.group_by(
        fn {kind, _user_id, _visitor_id} -> kind end,
        fn {_kind, user_id, visitor_id} -> learning_identity(user_id, visitor_id) end
      )
      |> Map.new(fn {kind, identities} -> {kind, MapSet.new(identities)} end)

    self_reported =
      Repo.all(
        from action in Action,
          where: action.action_type == "learned" and not is_nil(action.confirmed_at),
          select: action.user_id
      )
      |> MapSet.new(&"user:#{&1}")

    signal_identities =
      identities_by_kind
      |> Map.values()
      |> Enum.reduce(MapSet.new(), &MapSet.union/2)

    breakdown =
      Map.new(@learning_kinds, fn {kind, key} ->
        {key, identities_by_kind |> Map.get(kind, MapSet.new()) |> MapSet.size()}
      end)
      |> Map.put(:self_reported, MapSet.size(self_reported))

    %{
      people: signal_identities |> MapSet.union(self_reported) |> MapSet.size(),
      breakdown: breakdown
    }
  end

  defp learning_identity(user_id, _visitor_id) when is_binary(user_id), do: "user:#{user_id}"
  defp learning_identity(nil, visitor_id), do: "visitor:#{visitor_id}"

  @doc "Aggregate movement-building metrics without exposing supporter records."
  def metrics(today \\ Date.utc_today()) do
    user_count = Repo.aggregate(PauseAiCa.Accounts.User, :count)
    action_count = Repo.aggregate(from(a in Action, where: not is_nil(a.confirmed_at)), :count)

    visit_count =
      case Repo.aggregate(PauseAiCa.Engagement.DailyVisit, :sum, :count) do
        nil -> 0
        count -> Decimal.to_integer(count)
      end

    by_type =
      Repo.all(
        from a in Action,
          where: not is_nil(a.confirmed_at),
          group_by: a.action_type,
          order_by: [desc: count(a.id)],
          select: {a.action_type, count(a.id)}
      )

    active_people =
      Repo.one(
        from a in Action,
          where: not is_nil(a.confirmed_at),
          select: count(a.user_id, :distinct)
      )

    learning = learning_metrics()

    %{
      users: user_count,
      actions: action_count,
      active_people: active_people,
      visits: visit_count,
      learning_people: learning.people,
      learning_breakdown: learning.breakdown,
      by_type: by_type,
      trend_period: %{start: Date.add(today, -(@trend_days - 1)), end: today},
      trends: trends(today)
    }
  end

  defp trends(today) do
    dates = Enum.map((@trend_days - 1)..0//-1, &Date.add(today, -&1))
    first_day = hd(dates)

    account_counts =
      daily_counts(
        from u in PauseAiCa.Accounts.User,
          where: u.inserted_at >= ^DateTime.new!(first_day, ~T[00:00:00]),
          group_by: fragment("date(?)", u.inserted_at),
          select: {fragment("date(?)", u.inserted_at), count(u.id)}
      )

    action_counts =
      daily_counts(
        from a in Action,
          where: a.confirmed_at >= ^DateTime.new!(first_day, ~T[00:00:00]),
          group_by: fragment("date(?)", a.confirmed_at),
          select: {fragment("date(?)", a.confirmed_at), count(a.id)}
      )

    action_type_counts =
      Repo.all(
        from a in Action,
          where: a.confirmed_at >= ^DateTime.new!(first_day, ~T[00:00:00]),
          group_by: [a.action_type, fragment("date(?)", a.confirmed_at)],
          select: {a.action_type, fragment("date(?)", a.confirmed_at), count(a.id)}
      )
      |> Enum.group_by(fn {action_type, _date, _count} -> action_type end)
      |> Map.new(fn {action_type, counts} ->
        counts_by_date = Map.new(counts, fn {_action_type, date, count} -> {date, count} end)
        {action_type, fill_dates(dates, counts_by_date)}
      end)
      |> then(fn counts ->
        Map.new(Action.action_types(), fn action_type ->
          {action_type, Map.get(counts, action_type, List.duplicate(0, @trend_days))}
        end)
      end)

    first_confirmations =
      from a in Action,
        where: not is_nil(a.confirmed_at),
        group_by: a.user_id,
        select: %{user_id: a.user_id, first_confirmed_at: min(a.confirmed_at)}

    active_people_counts =
      daily_counts(
        from a in subquery(first_confirmations),
          where: a.first_confirmed_at >= ^DateTime.new!(first_day, ~T[00:00:00]),
          group_by: fragment("date(?)", a.first_confirmed_at),
          select: {fragment("date(?)", a.first_confirmed_at), count(a.user_id)}
      )

    visit_counts =
      Repo.all(
        from v in PauseAiCa.Engagement.DailyVisit,
          where: v.visited_on >= ^first_day and v.visited_on <= ^today,
          select: {v.visited_on, v.count}
      )
      |> Map.new()

    %{
      users: fill_dates(dates, account_counts),
      active_people: fill_dates(dates, active_people_counts),
      actions: fill_dates(dates, action_counts),
      action_types: action_type_counts,
      visits: fill_dates(dates, visit_counts)
    }
  end

  defp daily_counts(query), do: query |> Repo.all() |> Map.new()
  defp fill_dates(dates, counts), do: Enum.map(dates, &Map.get(counts, &1, 0))
end
