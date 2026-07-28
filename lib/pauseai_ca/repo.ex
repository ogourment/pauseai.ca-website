defmodule PauseAiCa.Repo do
  use Ecto.Repo,
    otp_app: :pauseai_ca,
    adapter: Ecto.Adapters.Postgres
end
