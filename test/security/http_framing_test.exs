defmodule PauseAiCa.HttpFramingTest do
  # These real TCP protocol checks are functional tests, not concurrent-load tests.
  # Isolate their bounded response wait from unrelated async database/logging work.
  use ExUnit.Case, async: false

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
    assert response(socket, "1;name=value\r\nx\r\n0\r\n\r\n", "keep-alive") == {200, "x"}
    assert response(socket, "1;name=value\r\nx\r\n0\r\n\r\n") == {200, "x"}
  end

  test "bare LF in a chunk extension is rejected before application dispatch", %{socket: socket} do
    assert {400, _body} = response(socket, "1;name=val\nue\r\nx\r\n0\r\n\r\n")
  end

  test "bare CR in a chunk extension is rejected before application dispatch", %{socket: socket} do
    assert {400, _body} = response(socket, "1;name=val\rue\r\nx\r\n0\r\n\r\n")
  end

  defp response(socket, body, connection \\ "close") do
    :ok =
      :gen_tcp.send(socket, [
        "POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\nConnection: ",
        connection,
        "\r\n\r\n",
        body
      ])

    receive_response(socket, "", System.monotonic_time(:millisecond) + 2_000)
  end

  defp receive_response(socket, response, deadline) do
    case complete_response(response) do
      {:ok, result} ->
        result

      :incomplete ->
        remaining = deadline - System.monotonic_time(:millisecond)
        if remaining <= 0, do: flunk("HTTP response deadline reached: #{inspect(response)}")

        case :gen_tcp.recv(socket, 0, remaining) do
          {:ok, data} ->
            receive_response(socket, response <> data, deadline)

          {:error, reason} ->
            flunk("HTTP response incomplete (#{inspect(reason)}): #{inspect(response)}")
        end
    end
  end

  defp complete_response(response) do
    case :binary.split(response, "\r\n\r\n") do
      [headers, body] ->
        [_, length] = Regex.run(~r/(?:^|\r\n)content-length:\s*(\d+)(?:\r\n|$)/i, headers)
        length = String.to_integer(length)

        if byte_size(body) >= length do
          [_, status | _] = String.split(headers, " ")
          {:ok, {String.to_integer(status), binary_part(body, 0, length)}}
        else
          :incomplete
        end

      [_partial] ->
        :incomplete
    end
  end
end
