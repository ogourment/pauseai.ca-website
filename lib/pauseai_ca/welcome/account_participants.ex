defmodule PauseAiCa.Welcome.AccountParticipants do
  @moduledoc "Existing scoped account access; an account relationship is not incubator membership."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.User
  alias PauseAiCa.Volunteers.Manager

  def list(scope, group_id) do
    if Enum.any?(Volunteers.groups(scope), &(&1.id == group_id)) do
      Repo.all(
        from u in User,
          left_join: m in Manager,
          on: m.user_id == u.id and m.group_id == ^group_id,
          where:
            not is_nil(u.confirmed_at) and
              (u.organizing_group_id == ^group_id or not is_nil(m.id)),
          order_by: u.email,
          distinct: true
      )
    else
      []
    end
  end

  def fetch(scope, group_id, user_id) do
    case Enum.find(list(scope, group_id), &(&1.id == user_id)) do
      nil -> {:error, :ineligible}
      user -> {:ok, user}
    end
  end
end
