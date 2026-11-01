defmodule PauseAiCa.HttpFramingTest do
  use ExUnit.Case, async: true

  defmodule Echo do
    def init(opts), do: opts

    def call(conn, _opts) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Plug.Conn.send_resp(conn, 200, body)
    end
  end

  setup do
    server = start_supervised!({Bandit, plug: Echo, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 2_000)
    on_exit(fn -> :gen_tcp.close(socket) end)
    %{socket: socket}
  end

  test "valid chunk extensions preserve the request body", %{socket: socket} do
    assert response(socket, "1;name=value\r\nx\r\n0\r\n\r\n") =~ "200 OK"
  end

  test "bare LF in a chunk extension is rejected before application dispatch", %{socket: socket} do
    assert response(socket, "1;name=val\nue\r\nx\r\n0\r\n\r\n") =~ "400 Bad Request"
  end

  test "bare CR in a chunk extension is rejected before application dispatch", %{socket: socket} do
    assert response(socket, "1;name=val\rue\r\nx\r\n0\r\n\r\n") =~ "400 Bad Request"
  end

  defp response(socket, body) do
    :ok =
      :gen_tcp.send(socket, [
        "POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n",
        body
      ])

    receive_response(socket, "")
  end

  defp receive_response(socket, response) do
    case :gen_tcp.recv(socket, 0, 2_000) do
      {:ok, data} -> receive_response(socket, response <> data)
      {:error, :closed} -> response
    end
  end
end
