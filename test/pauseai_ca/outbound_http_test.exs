defmodule PauseAiCa.OutboundHTTPTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  alias PauseAiCa.OutboundHTTP

  defmodule Provider do
    def init(opts), do: opts

    def call(conn, opts) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      attempt = Agent.get_and_update(opts.count, fn count -> {count, count + 1} end)
      send(opts.test, {:provider_received, attempt, body})

      if opts.mode == :blocked do
        send(opts.test, {:response_pending, self()})

        receive do
          :allow_response -> Plug.Conn.send_resp(conn, 200, "private-response")
        after
          2_000 -> Plug.Conn.send_resp(conn, 504, "private-response")
        end
      else
        status = if opts.mode == :retry and attempt == 0, do: 503, else: 200
        Plug.Conn.send_resp(conn, status, "private-response")
      end
    end
  end

  setup do
    previous_level = Logger.get_module_level(OutboundHTTP)
    Logger.put_module_level(OutboundHTTP, :info)

    on_exit(fn ->
      Logger.delete_module_level(OutboundHTTP)

      for {module, level} <- previous_level do
        Logger.put_module_level(module, level)
      end
    end)

    observer = start_supervised!({OutboundHTTP, &classify/1})
    %{observer: observer}
  end

  test "records separate real Req retries with sanitized metadata", %{observer: observer} do
    url = provider(:retry) <> "/recognized/private-path?token=private-query"
    assistant_id = Ecto.UUID.generate()
    request_id = Base.url_encode64("fixture-private")
    Logger.metadata(request_id: request_id)

    log =
      capture_log(fn ->
        assert {:ok, %{status: 200}} =
                 Req.post(url,
                   retry: :transient,
                   retry_delay: fn _attempt -> 0 end,
                   retry_log_level: false,
                   finch_private: %{
                     assistant_request_id: assistant_id,
                     assistant_stage: :jev,
                     assistant_direction: "output",
                     extra: "private-finch-value"
                   },
                   headers: [{"authorization", "Bearer private-header"}],
                   body: "private-request-body"
                 )

        :sys.get_state(observer)
      end)

    assert_receive {:provider_received, 0, "private-request-body"}
    assert_receive {:provider_received, 1, "private-request-body"}

    assert %{
             phase: "start",
             service: "fixture",
             operation: "recognized",
             method: "POST",
             attempt_id: first,
             assistant_request_id: ^assistant_id,
             assistant_stage: "jev",
             assistant_direction: "output",
             phoenix_request_ref: request_ref
           } = event(log, "start", 0)

    assert %{attempt_id: ^first, outcome: "http_error", status: "503", duration_ms: _} =
             event(log, "finish", 0)

    assert %{
             attempt_id: second,
             assistant_request_id: ^assistant_id,
             phoenix_request_ref: ^request_ref
           } =
             event(log, "start", 1)

    assert byte_size(request_ref) == 32
    refute log =~ request_id

    assert %{attempt_id: ^second, outcome: "completed", status: "200", duration_ms: _} =
             event(log, "finish", 1)

    refute first == second
    refute log =~ "private-"
    refute log =~ "127.0.0.1"
  end

  test "classifies unknown hosts safely and records a real transport failure", %{
    observer: observer
  } do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)

    log =
      capture_log(fn ->
        assert {:error, %Req.TransportError{}} =
                 Req.get("http://127.0.0.1:#{port}/private-path",
                   retry: false,
                   finch_private: %{
                     assistant_request_id: "private-invalid-id",
                     assistant_stage: :generation
                   }
                 )

        :sys.get_state(observer)
      end)

    assert %{service: "other_external", operation: "unknown", attempt_id: id} =
             event(log, "start")

    assert %{attempt_id: ^id, outcome: "transport_error", cause: "refused", duration_ms: _} =
             event(log, "finish")

    refute log =~ "private-path"
    refute log =~ "private-invalid-id"
    refute log =~ "assistant_request_id"
  end

  test "records streaming exceptions with no exception details", %{observer: observer} do
    url = provider(:success) <> "/recognized/private-path"

    log =
      capture_log(fn ->
        assert_raise RuntimeError, "private-exception", fn ->
          Req.get(url,
            retry: false,
            into: fn _, _ -> raise "private-exception" end
          )
        end

        :sys.get_state(observer)
      end)

    assert_receive {:provider_received, 0, ""}
    assert %{attempt_id: id} = event(log, "start")
    assert %{attempt_id: ^id, outcome: "exception", duration_ms: _} = event(log, "finish")
    refute log =~ "private-exception"
  end

  test "records the terminal outcome when a request worker is killed", %{observer: observer} do
    url = provider(:blocked) <> "/recognized/private-path"

    log =
      capture_log(fn ->
        {pid, monitor} = spawn_monitor(fn -> Req.get(url, retry: false) end)
        assert_receive {:provider_received, 0, ""}, 1_000
        assert_receive {:response_pending, provider}, 1_000
        await_attempt_count(observer, 1)
        Process.exit(pid, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 1_000
        await_attempt_count(observer, 0)
        send(provider, :allow_response)
      end)

    assert %{attempt_id: id} = event(log, "start")
    assert %{attempt_id: ^id, outcome: "abandoned", duration_ms: _} = event(log, "finish")
    refute log =~ "private-path"
  end

  defp classify(%Finch.Request{path: "/recognized/" <> _}), do: {:fixture, :recognized}
  defp classify(_), do: nil

  defp provider(mode) do
    count = start_supervised!({Agent, fn -> 0 end})
    plug = {Provider, %{test: self(), count: count, mode: mode}}
    server = start_supervised!({Bandit, plug: plug, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_address, port}} = ThousandIsland.listener_info(server)
    "http://127.0.0.1:#{port}"
  end

  defp event(log, phase, index \\ 0) do
    log
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "outbound_http phase=#{phase} "))
    |> Enum.fetch!(index)
    |> then(fn line -> Regex.scan(~r/(\w+)=([\w-]+)/, line) end)
    |> Map.new(fn [_pair, key, value] -> {String.to_existing_atom(key), value} end)
  end

  defp await_attempt_count(observer, count, polls \\ 100) do
    %{attempts: attempts} = :sys.get_state(observer)

    if map_size(attempts) == count or polls == 0 do
      assert map_size(attempts) == count
    else
      Process.sleep(10)
      await_attempt_count(observer, count, polls - 1)
    end
  end
end
