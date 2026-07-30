defmodule PauseAiCaWeb.AtddEvidence do
  @moduledoc false

  defdelegate reset!(title, scenarios, run_context), to: AcceptanceHarness.Evidence
  defdelegate record_step(name, title, description, metadata), to: AcceptanceHarness.Evidence
  defdelegate mark_scenario_success!(scenario), to: AcceptanceHarness.Evidence
  defdelegate finalize!(), to: AcceptanceHarness.Evidence
end
