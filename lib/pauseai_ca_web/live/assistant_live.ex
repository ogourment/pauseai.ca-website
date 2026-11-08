defmodule PauseAiCaWeb.AssistantLive do
  @moduledoc "Independent floating LiveView; fresh role/activation checks apply to every event."
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{Accounts, Assistant}
  alias PauseAiCa.Accounts.Scope

  def mount(_, session, socket) do
    {user, _} =
      (session["user_token"] && Accounts.get_user_by_session_token(session["user_token"])) ||
        {nil, nil}

    scope = Scope.for_user(user)

    mode =
      case Assistant.mode(scope) do
        {:ok, mode} -> mode
        _ -> "fast"
      end

    if connected?(socket) do
      Process.send_after(self(), :refresh_access, 15_000)
      Phoenix.PubSub.subscribe(PauseAiCa.PubSub, "agent_assistant:settings")
    end

    {conversation, messages} = load_conversation(scope)
    usage = load_usage(scope)

    {:ok,
     assign(socket,
       current_scope: scope,
       eligible: Assistant.launcher_visible?(scope),
       open: false,
       mode: mode,
       draft: "",
       messages: messages,
       conversation: conversation,
       usage: usage,
       pending: false,
       pending_text: "",
       error: nil,
       availability_error: availability_error(scope, usage, mode)
     )}
  end

  def handle_event(event, params, socket) do
    if Assistant.launcher_visible?(socket.assigns.current_scope),
      do: action(event, params, socket),
      else:
        {:noreply,
         assign(socket, eligible: false, open: false, messages: [], draft: "", pending: false)}
  end

  defp action("assistant-toggle", _, socket),
    do: {:noreply, assign(socket, open: !socket.assigns.open)}

  defp action("assistant-close", _, socket), do: {:noreply, assign(socket, open: false)}

  defp action("assistant-draft", %{"assistant" => %{"text" => text}}, socket)
       when is_binary(text) and byte_size(text) <= 16_000,
       do: {:noreply, assign(socket, draft: text)}

  defp action("assistant-mode", %{"mode" => mode} = params, socket) do
    text = get_in(params, ["assistant", "text"])

    socket =
      if is_binary(text) and byte_size(text) <= 16_000,
        do: assign(socket, draft: text),
        else: socket

    case Assistant.set_mode(socket.assigns.current_scope, mode) do
      {:ok, _} ->
        usage = load_usage(socket.assigns.current_scope)

        {:noreply,
         assign(socket,
           mode: mode,
           usage: usage,
           error: nil,
           availability_error: availability_error(socket.assigns.current_scope, usage, mode)
         )}

      _ ->
        {:noreply,
         assign(socket,
           error: gettext("This mode is unavailable. Your message has been retained.")
         )}
    end
  end

  defp action(
         "assistant-submit",
         %{"assistant" => %{"text" => text}},
         %{assigns: %{pending: false}} = socket
       )
       when is_binary(text) and byte_size(text) in 1..16_000 do
    scope = socket.assigns.current_scope
    request_id = Ecto.UUID.generate()
    conversation = socket.assigns.conversation
    locale = socket.assigns.locale

    usage = load_usage(scope)

    case availability_error(scope, usage, socket.assigns.mode) do
      nil ->
        socket =
          socket
          |> assign(
            pending: true,
            draft: text,
            pending_text: text,
            error: nil,
            usage: usage,
            availability_error: nil
          )
          |> start_async(:assistant_reply, fn ->
            Assistant.run(scope, request_id, text, conversation, locale)
          end)

        {:noreply, socket}

      reason ->
        {:noreply,
         assign(socket, draft: text, pending: false, usage: usage, availability_error: reason)}
    end
  end

  defp action("assistant-new", _, %{assigns: %{pending: false}} = socket) do
    case Assistant.new_conversation(socket.assigns.current_scope) do
      {:ok, reference} ->
        {:noreply, assign(socket, conversation: reference, messages: [], draft: "", error: nil)}

      _ ->
        {:noreply,
         assign(socket,
           error: gettext("The assistant is unavailable. Your message has been retained.")
         )}
    end
  end

  defp action(_, _, socket), do: {:noreply, socket}

  def handle_async(:assistant_reply, {:ok, {:ok, reply}}, socket) do
    if Assistant.launcher_visible?(socket.assigns.current_scope) do
      messages =
        socket.assigns.messages ++
          [
            %{role: "user", text: socket.assigns.pending_text},
            %{role: "assistant", text: reply.text}
          ]

      usage = load_usage(socket.assigns.current_scope)

      {:noreply,
       assign(socket,
         availability_error:
           availability_error(socket.assigns.current_scope, usage, socket.assigns.mode),
         messages: Enum.take(messages, -20),
         pending: false,
         pending_text: "",
         usage: usage,
         draft:
           if(socket.assigns.draft == socket.assigns.pending_text,
             do: "",
             else: socket.assigns.draft
           ),
         error: nil
       )}
    else
      {:noreply,
       assign(socket, eligible: false, messages: [], draft: "", pending: false, open: false)}
    end
  end

  def handle_async(:assistant_reply, _, socket) do
    usage = load_usage(socket.assigns.current_scope)

    {:noreply,
     assign(socket,
       pending: false,
       usage: usage,
       availability_error:
         availability_error(socket.assigns.current_scope, usage, socket.assigns.mode),
       error: gettext("The assistant is unavailable. Your message has been retained.")
     )}
  end

  def handle_info(:refresh_access, socket) do
    Process.send_after(self(), :refresh_access, 15_000)
    {:noreply, refresh(socket)}
  end

  def handle_info({:assistant_mode_changed, actor_id}, socket) do
    result =
      if socket.assigns.current_scope.user && socket.assigns.current_scope.user.id == actor_id,
        do: Assistant.mode(socket.assigns.current_scope),
        else: {:error, :not_current_actor}

    case result do
      {:ok, mode} ->
        usage = load_usage(socket.assigns.current_scope)

        {:noreply,
         assign(socket,
           mode: mode,
           usage: usage,
           availability_error: availability_error(socket.assigns.current_scope, usage, mode)
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info(:assistant_settings_changed, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    scope = socket.assigns.current_scope

    if Assistant.launcher_visible?(scope) do
      {reference, messages} =
        if socket.assigns.conversation,
          do: {socket.assigns.conversation, socket.assigns.messages},
          else: load_conversation(scope)

      usage = load_usage(scope)

      assign(socket,
        eligible: true,
        conversation: reference,
        messages: messages,
        usage: usage,
        availability_error: availability_error(scope, usage, socket.assigns.mode)
      )
    else
      assign(socket, eligible: false, open: false, messages: [], draft: "", conversation: nil)
    end
  end

  defp load_conversation(scope) do
    with {:ok, reference} <- Assistant.conversation(scope),
         {:ok, messages} <- Assistant.history(scope, reference) do
      {reference, messages}
    else
      _ -> {nil, []}
    end
  end

  defp load_usage(scope) do
    case Assistant.token_usage(scope) do
      {:ok, usage} -> usage
      _ -> nil
    end
  end

  defp availability_error(scope, usage, mode) do
    cond do
      is_map(usage) and Map.get(usage, :allocation_active, true) == false ->
        gettext("Assistant credit allocation is not ready. Your draft is retained.")

      not Assistant.visible?(scope) ->
        gettext("The assistant is temporarily unavailable. Your draft is retained.")

      is_nil(usage) ->
        gettext("Usage limits are temporarily unavailable. Your draft is retained.")

      usage.remaining_tokens == 0 ->
        gettext("Your daily token allowance is exhausted. Your draft is retained.")

      usage.remaining_cost_micros < usage.max_turn_cost_micros ->
        gettext("The daily cost allowance cannot cover another request. Your draft is retained.")

      not quality_available?(usage, mode) ->
        gettext("Choose an available mode. Higher modes are paused near a usage limit.")

      true ->
        nil
    end
  end

  defp quality_available?(usage, mode) do
    case Map.get(usage, :mode_availability) do
      nil -> true
      modes when is_map(modes) -> get_in(modes, [mode, :allowed]) == true
      _ -> false
    end
  end

  defp usage_summary(nil), do: nil

  defp usage_summary(usage) do
    locale = Gettext.get_locale(PauseAiCaWeb.Gettext)

    date =
      Calendar.strftime(
        usage.budget_reset_on,
        "%Y-%m-%d"
      )

    gettext("%{remaining} / %{limit} tokens remaining today",
      remaining: usage.remaining_tokens,
      limit: usage.limit
    ) <>
      " · " <>
      money_summary(usage, locale) <>
      " · " <> gettext("Budget resets on %{date} at 00:00 UTC", date: date)
  end

  defp money_summary(%{pending_cost_micros: pending} = usage, locale) do
    gettext("USD %{remaining} remaining today; USD %{pending} held for pending usage",
      remaining: usd(usage.remaining_cost_micros, locale),
      pending: usd(pending, locale)
    ) <>
      " · " <>
      gettext("USD %{remaining} of assistant allocation available",
        remaining: usd(usage.allocation_remaining_micros, locale)
      )
  end

  defp money_summary(usage, locale) do
    gettext("USD %{remaining} available for reservations; USD %{turn} reserved per request",
      remaining: usd(usage.remaining_cost_micros, locale),
      turn: usd(usage.max_turn_cost_micros, locale)
    )
  end

  defp usd(micros, locale) do
    separator = if locale == "fr", do: ",", else: "."

    Integer.to_string(div(micros, 1_000_000)) <>
      separator <>
      (rem(micros, 1_000_000)
       |> Integer.to_string()
       |> String.pad_leading(6, "0")
       |> String.trim_trailing("0")
       |> String.pad_trailing(2, "0"))
  end

  def render(assigns) do
    ~H"""
    <PhoenixAgentAssistant.Components.assistant
      id="site-assistant"
      enabled={@eligible}
      eligible={@eligible}
      open={@open}
      mode={@mode}
      mode_availability={if @usage, do: Map.get(@usage, :mode_availability, %{}), else: %{}}
      draft={@draft}
      messages={@messages}
      pending={@pending}
      error={@availability_error || @error}
      allow_new={true}
      usage_summary={usage_summary(@usage)}
      quota_exhausted={not is_nil(@availability_error)}
      labels={
        %{
          "fast" => gettext("Fast"),
          "normal" => gettext("Normal"),
          "high" => gettext("High"),
          assistant: gettext("Assistant"),
          new_conversation: gettext("New conversation"),
          move: gettext("Move assistant with arrow keys"),
          send: gettext("Send"),
          close: gettext("Close assistant"),
          minimize: gettext("Minimize assistant"),
          expand: gettext("Expand assistant"),
          mode: gettext("Mode"),
          budget_limited: gettext("Near usage limit"),
          message: gettext("Message"),
          working: gettext("Working…"),
          placeholder: gettext("How can I help?")
        }
      }
    />
    """
  end
end
