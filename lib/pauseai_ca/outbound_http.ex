defmodule PauseAiCa.OutboundHTTP do
  @moduledoc """
  Records sanitized outbound HTTP attempts from Finch, including requests made by Req and Swoosh.

  The host classifier receives the Finch request and returns fixed service and operation atoms.
  Request data stays in the calling process. The observer retains only the classification,
  validated correlation fields, and timing. It monitors each caller so attempts interrupted
  by process exit have a terminal record.
  """

  use GenServer
  require Logger

  @events for phase <- [:start, :stop, :exception], do: [:finch, :request, phase]
  @methods ~w(GET HEAD POST PUT PATCH DELETE OPTIONS TRACE CONNECT)

  def start_link(classifier) when is_function(classifier, 1) do
    GenServer.start_link(__MODULE__, classifier, name: __MODULE__)
  end

  @impl true
  def init(classifier) do
    # A supervisor restart after an untrappable exit may leave the old handler installed.
    :telemetry.detach(__MODULE__)

    :ok =
      :telemetry.attach_many(
        __MODULE__,
        @events,
        &__MODULE__.handle_event/4,
        {self(), classifier, :crypto.strong_rand_bytes(32)}
      )

    {:ok, %{attempts: %{}, spans: %{}}}
  end

  @impl true
  def terminate(_reason, _state), do: :telemetry.detach(__MODULE__)

  @doc false
  def handle_event(
        [:finch, :request, :start],
        _,
        metadata,
        {observer, classifier, correlation_key}
      ) do
    %{request: request, telemetry_span_context: span} = metadata
    {service, operation} = classify(classifier, request)

    attempt = %{
      attempt_id: Ecto.UUID.generate(),
      service: service,
      operation: operation,
      method: method(request.method),
      correlation: assistant_fields(request.private) ++ phoenix_fields(correlation_key),
      started_at: System.monotonic_time()
    }

    GenServer.cast(observer, {:start, span, self(), attempt})
  end

  def handle_event([:finch, :request, :stop], %{duration: duration}, metadata, {observer, _, _}) do
    fields = result(metadata.result)

    GenServer.cast(
      observer,
      {:finish, metadata.telemetry_span_context, fields, duration}
    )
  end

  def handle_event(
        [:finch, :request, :exception],
        %{duration: duration},
        metadata,
        {observer, _, _}
      ) do
    GenServer.cast(
      observer,
      {:finish, metadata.telemetry_span_context, [outcome: :exception], duration}
    )
  end

  @impl true
  def handle_cast({:start, span, caller, attempt}, state) do
    ref = Process.monitor(caller)
    record(attempt, :start)

    {:noreply,
     %{
       attempts: Map.put(state.attempts, span, {ref, attempt}),
       spans: Map.put(state.spans, ref, span)
     }}
  end

  def handle_cast({:finish, span, fields, duration}, state) do
    {:noreply, finish(state, span, fields, duration)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.fetch(state.spans, ref) do
      {:ok, span} -> {:noreply, finish(state, span, [outcome: :abandoned], nil)}
      :error -> {:noreply, state}
    end
  end

  defp finish(state, span, fields, duration) do
    case Map.pop(state.attempts, span) do
      {nil, _attempts} ->
        state

      {{ref, attempt}, attempts} ->
        Process.demonitor(ref, [:flush])
        duration = duration || System.monotonic_time() - attempt.started_at
        duration_ms = System.convert_time_unit(duration, :native, :millisecond)
        record(attempt, :finish, fields ++ [duration_ms: duration_ms])
        %{attempts: attempts, spans: Map.delete(state.spans, ref)}
    end
  end

  defp classify(classifier, request) do
    case classifier.(request) do
      {service, operation} when is_atom(service) and is_atom(operation) -> {service, operation}
      _ -> {:other_external, :unknown}
    end
  rescue
    _ -> {:other_external, :unknown}
  catch
    _, _ -> {:other_external, :unknown}
  end

  defp method(method) when method in @methods, do: method
  defp method(_method), do: "OTHER"

  defp result({:ok, %Finch.Response{status: status}}), do: response_status(status)

  # Req's Finch stream accumulator carries the status for buffered and callback responses.
  defp result({:ok, {%Req.Request{}, {status, _, _, _}}}), do: response_status(status)
  defp result({:ok, {%Req.Request{}, %Req.Response{status: status}}}), do: response_status(status)

  defp result({:ok, {%Req.Request{}, {_collectable, %Req.Response{status: status}}}}),
    do: response_status(status)

  defp result({:ok, _accumulator}), do: [outcome: :completed]
  defp result({:error, reason}), do: transport_error(reason)
  defp result({:error, reason, _accumulator}), do: transport_error(reason)
  defp result(_result), do: [outcome: :unknown]

  defp response_status(status) when is_integer(status) and status in 100..599 do
    [outcome: if(status < 400, do: :completed, else: :http_error), status: status]
  end

  defp response_status(_status), do: [outcome: :completed]

  defp transport_error(%{reason: reason}),
    do: [outcome: :transport_error, cause: transport_cause(reason)]

  defp transport_error(_reason), do: [outcome: :transport_error, cause: :unknown]

  defp transport_cause(:timeout), do: :timeout
  defp transport_cause(reason) when reason in [:closed, :econnreset], do: :closed
  defp transport_cause(:econnrefused), do: :refused
  defp transport_cause(:nxdomain), do: :dns
  defp transport_cause({:tls_alert, _}), do: :tls
  defp transport_cause(_reason), do: :unknown

  defp assistant_fields(%{assistant_request_id: id, assistant_stage: stage} = private) do
    with {:ok, id} <- uuid(id) do
      case {stage, Map.get(private, :assistant_direction)} do
        {:generation, nil} ->
          [assistant_request_id: id, assistant_stage: :generation]

        {stage, direction}
        when stage in [:moderation, :jev] and direction in ["input", "output"] ->
          [assistant_request_id: id, assistant_stage: stage, assistant_direction: direction]

        _ ->
          []
      end
    else
      :error -> []
    end
  end

  defp assistant_fields(_private), do: []

  defp uuid(id) when is_binary(id) and byte_size(id) == 36, do: Ecto.UUID.cast(id)
  defp uuid(_id), do: :error

  defp phoenix_fields(key) do
    with id when is_binary(id) and byte_size(id) == 20 <- Logger.metadata()[:request_id],
         {:ok, <<_::120>>} <- Base.url_decode64(id, padding: false) do
      # Plug can use an inbound request header as its request ID. Keep only a keyed correlation.
      mac = :crypto.mac(:hmac, :sha256, key, id) |> binary_part(0, 16)
      [phoenix_request_ref: Base.encode16(mac, case: :lower)]
    else
      _ -> []
    end
  end

  defp record(attempt, phase, fields \\ []) do
    fields =
      [
        phase: phase,
        attempt_id: attempt.attempt_id,
        service: attempt.service,
        operation: attempt.operation,
        method: attempt.method
      ] ++ attempt.correlation ++ fields

    fields = Enum.reject(fields, fn {_key, value} -> is_nil(value) end)

    Logger.info(
      fn ->
        "outbound_http " <>
          Enum.map_join(fields, " ", fn {key, value} ->
            "#{key}=#{value}"
          end)
      end,
      fields
    )
  end
end
