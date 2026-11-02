defmodule PauseAiCa.Outreach.IdentityPolicy do
  @moduledoc "Narrow CRM creation adapter for a freshly authorized mailbox; no directory access."
  @behaviour PhoenixCRM.Policy
  import Ecto.Query

  def authorize(%{scope: scope, mailbox_ref: ref}, :create, nil) do
    if PauseAiCa.Outreach.Access.allowed?(scope, ref), do: :ok, else: {:error, :unauthorized}
  end

  def authorize(_, _, _), do: {:error, :unauthorized}
  def scope(_, query), do: where(query, [row], false)
  def actor_id(%{scope: %{user: %{id: id}}}), do: id
  def recipient(_, _, _), do: {:error, :ineligible}
end
