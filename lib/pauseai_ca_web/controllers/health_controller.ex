defmodule PauseAiCaWeb.HealthController do
  use PauseAiCaWeb, :controller

  def check(conn, _params) do
    {status, payload} = PauseAiCa.Health.check()
    conn |> put_status(status) |> json(payload)
  end
end
