defmodule PauseAiCaWeb.AssistantInstructionAccess do
  @moduledoc false
  import Plug.Conn

  def init(options), do: options

  def call(conn, _) do
    conn = register_before_send(conn, &put_resp_header(&1, "cache-control", "private, no-store"))

    if PauseAiCa.Assistant.Instructions.permitted?(conn.assigns[:current_scope]),
      do: conn,
      else: conn |> send_resp(404, "Not found") |> halt()
  end
end
