defmodule PauseAiCa.CRM.Policy do
  @behaviour PhoenixCRM.Policy
  import Ecto.Query
  alias PauseAiCa.Volunteers

  def authorize(scope, _action, _person),
    do: if(Volunteers.superadmin?(scope), do: :ok, else: {:error, :unauthorized})

  def scope(scope, query),
    do: if(Volunteers.superadmin?(scope), do: query, else: where(query, [p], false))

  def actor_id(%{user: %{id: id}}), do: id

  # CRM identity and preference never grant purpose eligibility. The account adapter owns draft preparation.
  def recipient(_scope, _record, _purpose), do: {:error, :ineligible}
end
