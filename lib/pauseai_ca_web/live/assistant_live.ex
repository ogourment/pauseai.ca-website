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

    {:ok,
     assign(socket,
       current_scope: scope,
       eligible: Assistant.visible?(scope),
       open: false,
       mode: mode,
       draft: "",
       messages: messages,
       conversation: conversation,
       usage: load_usage(scope),
       pending: false,
       pending_text: "",
       error: nil
     )}
  end

  def handle_event(event, params, socket) do
    if Assistant.visible?(socket.assigns.current_scope),
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
        {:noreply, assign(socket, mode: mode, error: nil)}

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

    socket =
      socket
      |> assign(pending: true, draft: text, pending_text: text, error: nil)
      |> start_async(:assistant_reply, fn ->
        Assistant.run(scope, request_id, text, conversation, locale)
      end)

    {:noreply, socket}
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
    if Assistant.visible?(socket.assigns.current_scope) do
      messages =
        socket.assigns.messages ++
          [
            %{role: "user", text: socket.assigns.pending_text},
            %{role: "assistant", text: reply.text}
          ]

      {:noreply,
       assign(socket,
         messages: Enum.take(messages, -20),
         pending: false,
         pending_text: "",
         usage: load_usage(socket.assigns.current_scope),
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

  def handle_async(:assistant_reply, _, socket),
    do:
      {:noreply,
       assign(socket,
         pending: false,
         usage: load_usage(socket.assigns.current_scope),
         error: gettext("The assistant is unavailable. Your message has been retained.")
       )}

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
      {:ok, mode} -> {:noreply, assign(socket, mode: mode)}
      _ -> {:noreply, socket}
    end
  end

  def handle_info(:assistant_settings_changed, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    scope = socket.assigns.current_scope

    if Assistant.visible?(scope) do
      {reference, messages} =
        if socket.assigns.conversation,
          do: {socket.assigns.conversation, socket.assigns.messages},
          else: load_conversation(scope)

      assign(socket,
        eligible: true,
        conversation: reference,
        messages: messages,
        usage: load_usage(scope)
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

  defp usage_summary(nil), do: nil

  defp usage_summary(usage),
    do:
      gettext("%{remaining} / %{limit} tokens remaining today",
        remaining: usage.remaining_tokens,
        limit: usage.limit
      )

  def render(assigns) do
    ~H"""
    <PhoenixAgentAssistant.Components.assistant
      id="site-assistant"
      enabled={@eligible}
      eligible={@eligible}
      open={@open}
      mode={@mode}
      draft={@draft}
      messages={@messages}
      pending={@pending}
      error={@error}
      allow_new={true}
      usage_summary={usage_summary(@usage)}
      quota_exhausted={not is_nil(@usage) and @usage.remaining_tokens == 0}
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
          message: gettext("Message"),
          working: gettext("Working…"),
          placeholder: gettext("How can I help?")
        }
      }
    />
    """
  end
end
