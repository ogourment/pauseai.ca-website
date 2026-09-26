defmodule PauseAiCa.VolunteerMailAdapter do
  use Swoosh.Adapter

  def deliver(email, config) do
    [{_, recipient}] = email.to

    case Application.get_env(:pauseai_ca, :volunteer_test_outcomes, %{})[recipient] do
      :rejected ->
        {:error, :rejected}

      :unknown ->
        {:error, :timeout}

      _ ->
        with {:ok, _} <- Swoosh.Adapters.Test.deliver(email, config),
             do: {:ok, %{id: "test-provider-" <> Ecto.UUID.generate()}}
    end
  end
end
