defmodule PauseAiCa.Welcome.AccountParticipants do
  @moduledoc "Confirmed group relationships, including pending admission, authorize welcome selection only."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Accounts.User
  alias PauseAiCa.Volunteers.Manager
  alias PauseAiCa.Incubators.Membership

  def list(scope, group_id) do
    if Enum.any?(Volunteers.groups(scope), &(&1.id == group_id)),
      do: Repo.all(query(group_id)),
      else: []
  end

  def fetch(scope, group_id, user_id) do
    case Enum.find(list(scope, group_id), &(&1.id == user_id)) do
      nil -> {:error, :ineligible}
      user -> {:ok, user}
    end
  end

  def related?(user_id, group_id),
    do: Repo.exists?(from u in query(group_id), where: u.id == ^user_id)

  defp query(group_id) do
    from u in User,
      left_join: m in Manager,
      on: m.user_id == u.id and m.group_id == ^group_id,
      left_join: admission in Membership,
      on: admission.user_id == u.id and admission.group_id == ^group_id,
      where:
        not is_nil(u.confirmed_at) and
          ((is_nil(admission.id) and
              (u.organizing_group_id == ^group_id or not is_nil(m.id))) or
             admission.status in ["pending", "approved", "admitted"]),
      order_by: u.email,
      distinct: true
  end
end
