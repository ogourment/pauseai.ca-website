defmodule PauseAiCa.MintResponseTest do
  use ExUnit.Case, async: false

  test "valid response chunk extensions preserve the body" do
    assert {:ok, conn, events} = response("1;name=value\r\nx\r\n0\r\n\r\n")
    on_exit(fn -> Mint.HTTP1.close(conn) end)
    assert Enum.any?(events, &match?({:data, _, "x"}, &1))
    assert Enum.any?(events, &match?({:done, _}, &1))
  end

  test "invalid chunk extension tails reject the response" do
    assert {:error, conn, %Mint.HTTPError{}, _events} =
             response("1 garbage\r\nx\r\n0\r\n\r\n")

    refute Mint.HTTP1.open?(conn)
  end

  defp response(body) do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_tcp.close(listener) end)
    {:ok, port} = :inet.port(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 2_000)
        {:ok, _request} = :gen_tcp.recv(socket, 0, 2_000)

        :ok =
          :gen_tcp.send(socket, ["HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n", body])

        :gen_tcp.close(socket)
      end)

    {:ok, conn} = Mint.HTTP1.connect(:http, "127.0.0.1", port, mode: :passive)
    {:ok, conn, _ref} = Mint.HTTP1.request(conn, "GET", "/", [], nil)
    result = Mint.HTTP1.recv(conn, 0, 2_000)
    Task.await(server, 3_000)
    result
  end
end
