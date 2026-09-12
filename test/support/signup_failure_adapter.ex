defmodule PauseAiCa.SignupFailureAdapter do
  use Swoosh.Adapter
  def deliver(_email, _config), do: {:error, :temporary_failure}
end
