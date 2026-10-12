defmodule PauseAiCaWeb.SourceIntakeController do
  use PauseAiCaWeb, :controller

  def create(conn, params) do
    token = Application.get_env(:pauseai_ca, :crm_intake_token)
    supplied = get_req_header(conn, "authorization")

    if is_binary(token) and byte_size(token) >= 32 and
         supplied != [] and Plug.Crypto.secure_compare(hd(supplied), "Bearer " <> token) do
      case params do
        %{"source" => source, "event_id" => event_id, "rows" => rows} ->
          case PauseAiCa.SourceIntake.ingest(source, event_id, rows) do
            {:ok, result} ->
              json(conn, result)

            {:error, :event_conflict} ->
              conn |> put_status(409) |> json(%{error: "event_conflict"})

            {:error, _} ->
              conn |> put_status(422) |> json(%{error: "invalid_observation"})
          end

        _ ->
          conn |> put_status(422) |> json(%{error: "invalid_payload"})
      end
    else
      conn |> put_status(401) |> json(%{error: "unauthorized"})
    end
  end
end
