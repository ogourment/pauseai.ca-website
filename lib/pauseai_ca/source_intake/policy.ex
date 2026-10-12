defmodule PauseAiCa.SourceIntake.Policy do
  @moduledoc false
  @behaviour PhoenixCRM.Policy
  import Ecto.Query
  def authorize(:source_intake, :import, _), do: :ok
  def authorize(_, _, _), do: {:error, :unauthorized}
  def scope(_, query), do: where(query, [p], false)
  def actor_id(:source_intake), do: "service:source-intake"
  def recipient(_, _, _), do: {:error, :ineligible}
end
