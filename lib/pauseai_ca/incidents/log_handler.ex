defmodule PauseAiCa.Incidents.LogHandler do
  @moduledoc "OTP Logger handler. Only code locations and exception classes leave the logger."
  def log(%{meta: meta}, _) do
    unless Process.get(:pauseai_reporting) do
      case meta[:crash_reason] do
        {reason, stack} when is_list(stack) ->
          if unexpected?(reason) do
            frame = Enum.find(stack, &app_frame?/1) || List.first(stack)

            category =
              if is_exception(reason), do: inspect(reason.__struct__), else: "process_crash"

            PauseAiCa.Incidents.server(category, location(frame))
          end

        _ ->
          case meta[:mfa] do
            {module, _, _} = frame when is_atom(module) ->
              PauseAiCa.Incidents.server("logged_error", location(frame))

            _ ->
              PauseAiCa.Incidents.server("logged_error", "unknown")
          end
      end
    end

    :ok
  rescue
    _ -> :ok
  end

  defp unexpected?(reason) when reason in [:normal, :shutdown], do: false
  defp unexpected?({:shutdown, _}), do: false
  defp unexpected?(%{__exception__: true} = reason), do: Plug.Exception.status(reason) >= 500
  defp unexpected?(_), do: true

  defp app_frame?({mod, _, _, _}) when is_atom(mod),
    do: String.starts_with?(Atom.to_string(mod), "Elixir.PauseAiCa")

  defp app_frame?(_), do: false
  defp location({m, f, a, _}), do: location({m, f, a})
  defp location({m, f, _}) when is_atom(m) and is_atom(f), do: "#{inspect(m)}.#{f}"
  defp location(_), do: "unknown"
end
