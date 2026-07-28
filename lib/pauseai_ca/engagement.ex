defmodule PauseAiCa.Engagement do
  @moduledoc """
  The Engagement context.
  """

  import Ecto.Query, warn: false
  alias PauseAiCa.Repo

  alias PauseAiCa.Engagement.Action
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
end
