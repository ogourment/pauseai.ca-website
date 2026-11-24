defmodule PauseAiCaWeb.AssistantLive do
  @moduledoc "Independent floating LiveView; fresh role/activation checks apply to every event."
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.{Accounts, Assistant}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Assistant.GuidedMode, as: Guide

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

      if user do
        Phoenix.PubSub.subscribe(PauseAiCa.PubSub, Guide.topic(user.id))
        Phoenix.PubSub.subscribe(PauseAiCa.PubSub, "agent_assistant:review:" <> user.id)
      end
    end

    {conversation, messages} = load_conversation(scope)
    usage = load_usage(scope)

    {:ok,
     assign(socket,
       current_scope: scope,
       admin_controls: Assistant.eligible?(scope),
       guide_session: %{
         id: Ecto.UUID.generate(),
         login: Guide.session_fingerprint(session["user_token"])
       },
       guide_mode: false,
       guide_state: nil,
       guide_count: nil,
       guide_error: nil,
       guide_available: guide_available?(scope, socket.assigns.locale),
       pending_guided: false,
       eligible: Assistant.launcher_visible?(scope),
       open: false,
       mode: mode,
       draft: "",
       messages: messages,
       conversation: conversation,
       usage: usage,
       pending: false,
       pending_text: "",
       pending_request_id: nil,
       review_refresh_required: nil,
       error: nil,
       availability_error: availability_error(scope, usage, mode)
     )}
  end

  def handle_event(event, params, socket) do
    if Assistant.launcher_visible?(socket.assigns.current_scope),
      do: action(event, params, socket),
      else:
        {:noreply,
         assign(socket,
           eligible: false,
           open: false,
           messages: [],
           draft: "",
           pending: false,
           guide_state: nil
         )}
  end

  defp action(
         "assistant-guided-mode",
         %{"enabled" => value},
         %{assigns: %{pending: false}} = socket
       )
       when value in ["true", "false"] do
    enabled =
      value == "true" and guide_available?(socket.assigns.current_scope, socket.assigns.locale)

    {:noreply, assign(socket, guide_mode: enabled, guide_error: nil)}
  end

  defp action("assistant-guide-next", _, %{assigns: %{guide_state: state}} = socket)
       when is_map(state) do
    case Guide.next(
           socket.assigns.current_scope,
           state,
           socket.assigns.locale,
           socket.assigns.guide_session
         ) do
      {:ok, pending, command} ->
        {:noreply,
         socket
         |> assign(guide_state: pending, guide_error: nil)
         |> push_event("paa:guided-command", command)}

      _ ->
        {:noreply, guide_failed(socket)}
    end
  end

  defp action("assistant-guide-back", _, %{assigns: %{guide_state: state}} = socket)
       when is_map(state) do
    case Guide.back(
           socket.assigns.current_scope,
           state,
           socket.assigns.locale,
           socket.assigns.guide_session
         ) do
      {:ok, previous} ->
        {:noreply,
         socket
         |> assign(guide_state: previous, guide_count: nil, guide_error: nil)
         |> push_event("paa:guided-clear", %{})}

      _ ->
        {:noreply, guide_failed(socket)}
    end
  end

  defp action("assistant-guide-exit", _, socket) do
    Guide.exit(socket.assigns.current_scope, socket.assigns.locale)

    {:noreply,
     socket |> assign(guide_state: nil, guide_error: nil) |> push_event("paa:guided-clear", %{})}
  end

  defp action("assistant-guide-failed", %{"token" => token, "category" => category}, socket) do
    if socket.assigns.guide_state && socket.assigns.guide_state.token == token do
      Guide.failed(socket.assigns.current_scope, socket.assigns.locale, category)
      {:noreply, guide_failed(socket)}
    else
      {:noreply, socket}
    end
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
    guided = socket.assigns.guide_mode

    usage = load_usage(scope)

    case availability_error(scope, usage, socket.assigns.mode) do
      nil ->
        socket =
          socket
          |> assign(
            pending: true,
            draft: text,
            pending_text: text,
            pending_request_id: request_id,
            pending_guided: guided,
            error: nil,
            usage: usage,
            availability_error: nil
          )
          |> start_async(:assistant_reply, fn ->
            Assistant.run(scope, request_id, text, conversation, locale, guided_mode: guided)
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
        {:noreply,
         socket
         |> push_event("paa:draft-clear", %{key: draft_key(socket.assigns)})
         |> assign(conversation: reference, messages: [], draft: "", error: nil)}

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
      {socket, response_text} = reviewed_guide(socket, reply.text)

      messages =
        socket.assigns.messages ++
          [
            %{role: "user", text: socket.assigns.pending_text},
            %{role: "assistant", text: response_text}
          ]

      usage = load_usage(socket.assigns.current_scope)

      socket =
        if is_nil(socket.assigns.guide_error) do
          push_event(socket, "paa:draft-clear", %{
            key: draft_key(socket.assigns),
            text: socket.assigns.pending_text
          })
        else
          socket
        end

      {:noreply,
       assign(socket,
         availability_error:
           availability_error(socket.assigns.current_scope, usage, socket.assigns.mode),
         messages: Enum.take(messages, -20),
         pending: false,
         pending_text: "",
         usage: usage,
         draft:
           if(
             is_nil(socket.assigns.guide_error) and
               socket.assigns.draft == socket.assigns.pending_text,
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

  def handle_async(:assistant_reply, {:ok, {:error, reason}}, socket)
      when reason in [:request_too_large, :token_limit_unavailable] do
    message =
      case reason do
        :request_too_large ->
          gettext(
            "This request exceeds the assistant’s per-request limit. Shorten your message or start a new conversation. Your message has been retained."
          )

        :token_limit_unavailable ->
          gettext(
            "The assistant could not check its request limit. Your message has been retained."
          )
      end

    {:noreply,
     assign(socket,
       pending: false,
       usage: load_usage(socket.assigns.current_scope),
       error: message
     )}
  end

  def handle_async(:assistant_reply, {:ok, {:error, reason}}, socket)
      when reason in [
             :input_safety_review_required,
             :input_safety_blocked,
             :input_safety_unavailable,
             :output_safety_review_required,
             :output_safety_blocked,
             :output_safety_unavailable
           ] do
    message =
      case reason do
        :input_safety_unavailable ->
          gettext(
            "The Assistant couldn't check your question, so it stopped before answering. Your question is still here. You can try again later."
          )

        :input_safety_blocked ->
          gettext(
            "The safety check blocked this request. The Assistant can help you use the website, but it can't share private records. If you're trying to email people, describe the group you want to reach without pasting addresses. Ask how to contact them through the CRM."
          )

        :input_safety_review_required ->
          gettext(
            "Your question needs a safety review before the Assistant can answer. Your message is saved for review."
          )

        :output_safety_unavailable ->
          gettext(
            "An answer was generated, but its review could not complete. Your message is retained."
          )

        _ ->
          gettext(
            "An answer was generated and held by the output review. Your message is retained."
          )
      end

    {:noreply,
     assign(socket,
       pending: false,
       usage: load_usage(socket.assigns.current_scope),
       error: message
     )}
  end

  def handle_async(:assistant_reply, {:ok, {:error, :provider_failed}}, socket) do
    usage = load_usage(socket.assigns.current_scope)

    {:noreply,
     assign(socket,
       pending: false,
       usage: usage,
       availability_error:
         availability_error(socket.assigns.current_scope, usage, socket.assigns.mode),
       error: gettext("The provider could not return a usable answer. Your message is retained.")
     )}
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

  def handle_info({:guided_page_observed, observation}, socket) do
    state = socket.assigns.guide_state

    if state && state.token == observation["token"] do
      case Guide.acknowledge(
             socket.assigns.current_scope,
             state,
             observation,
             socket.assigns.locale,
             socket.assigns.guide_session
           ) do
        {:ok, advanced, count} ->
          {:noreply, assign(socket, guide_state: advanced, guide_count: count)}

        {:waiting, waiting} ->
          {:noreply, assign(socket, guide_state: waiting)}

        {:waiting, waiting, command} ->
          {:noreply,
           socket |> assign(guide_state: waiting) |> push_event("paa:guided-command", command)}

        _ ->
          {:noreply, guide_failed(socket)}
      end
    else
      {:noreply, socket}
    end
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

  def handle_info({:assistant_review_decided, conversation, notice}, socket) do
    if socket.assigns.conversation == conversation do
      socket = assign(socket, review_refresh_required: notice)
      {:noreply, refresh(socket)}
    else
      {:noreply, refresh(socket)}
    end
  end

  def handle_info(:assistant_settings_changed, socket), do: {:noreply, refresh(socket)}

  defp refresh_review(socket) do
    notice = socket.assigns.review_refresh_required

    if notice && not socket.assigns.pending do
      case Assistant.history(socket.assigns.current_scope, socket.assigns.conversation) do
        {:ok, messages} ->
          same_request = socket.assigns.pending_request_id in [nil, notice.request_ref]
          {socket, messages} = reviewed_continuation(socket, messages, notice, same_request)

          clear =
            notice.status == :approved and same_request and is_nil(socket.assigns.guide_error) and
              socket.assigns.draft == notice.question

          socket =
            if clear,
              do:
                push_event(socket, "paa:draft-clear", %{
                  key: draft_key(socket.assigns),
                  text: notice.question
                }),
              else: socket

          error =
            cond do
              socket.assigns.pending_request_id != notice.request_ref ->
                socket.assigns.error

              notice.status == :approved ->
                nil

              notice.status == :rejected and notice.phase == :input ->
                gettext(
                  "The request was rejected after superadmin review. Your message is retained."
                )

              notice.status == :output_held ->
                gettext(
                  "An answer was generated and held by the output review. Your message is retained."
                )

              true ->
                gettext(
                  "The held answer was rejected after human review. Your message is retained."
                )
            end

          assign(socket,
            messages: messages,
            pending_request_id:
              if(same_request and is_binary(notice.followup_ref),
                do: notice.followup_ref,
                else: socket.assigns.pending_request_id
              ),
            review_refresh_required: nil,
            error: error,
            draft: if(clear, do: "", else: socket.assigns.draft)
          )

        _ ->
          socket
      end
    else
      socket
    end
  end

  defp reviewed_continuation(socket, messages, notice, same_request) do
    if same_request and is_binary(notice.followup_ref) and notice.status == :approved do
      case List.pop_at(messages, -1) do
        {%{role: "assistant", text: text} = last, previous} ->
          {socket, display} = reviewed_guide(socket, text)
          {socket, previous ++ [%{last | text: display}]}

        _ ->
          {socket, messages}
      end
    else
      {socket, messages}
    end
  end

  defp refresh(socket) do
    scope = socket.assigns.current_scope

    if Assistant.launcher_visible?(scope) do
      socket = refresh_review(socket)

      {reference, messages} =
        if socket.assigns.conversation,
          do: {socket.assigns.conversation, socket.assigns.messages},
          else: load_conversation(scope)

      usage = load_usage(scope)

      assign(socket,
        eligible: true,
        admin_controls: Assistant.eligible?(scope),
        guide_available: guide_available?(scope, socket.assigns.locale),
        conversation: reference,
        messages: messages,
        usage: usage,
        availability_error: availability_error(scope, usage, socket.assigns.mode)
      )
    else
      assign(socket,
        eligible: false,
        open: false,
        messages: [],
        draft: "",
        conversation: nil,
        guide_state: nil
      )
    end
  end

  defp guide_available?(scope, locale), do: match?({:ok, _, _}, Guide.manifest(scope, locale))

  defp reviewed_guide(%{assigns: %{pending_guided: true}} = socket, text) do
    case Guide.start(
           socket.assigns.current_scope,
           text,
           socket.assigns.locale,
           socket.assigns.guide_session
         ) do
      {:ok, state} ->
        {assign(socket, guide_state: state, guide_error: nil, guide_count: nil, open: false),
         gettext("Your guide is ready. Use Next to continue.")}

      _ ->
        {assign(socket,
           guide_error: gettext("The guide could not be verified. Your message is retained.")
         ), gettext("The guide could not be verified. Your message is retained.")}
    end
  end

  defp reviewed_guide(socket, text), do: {socket, text}

  defp guide_failed(socket) do
    socket
    |> assign(
      guide_state: PhoenixAgentAssistant.GuidedMode.fail(socket.assigns.guide_state),
      guide_error:
        gettext("This page or your access changed. The guide stopped. Use Back or Exit.")
    )
    |> push_event("paa:guided-clear", %{})
  end

  defp guide_title(nil, _), do: ""

  defp guide_title(%{plan: %{"journey" => "crm.vancouver_workflow"}} = state, _count) do
    case state.index do
      0 ->
        gettext("Step 1 of 5 · Open Contacts.")

      1 ->
        gettext("Step 2 of 5 · Choose Vancouver in Cities and preview the matches.")

      2 ->
        gettext("Step 3 of 5 · Open Lists.")

      3 ->
        gettext(
          "Step 4 of 5 · Name a dynamic list, set city to Vancouver, then choose Save list."
        )

      4 ->
        gettext("Step 5 of 5 · Review the saved list, then choose Compose newsletter.")

      _ ->
        gettext("Complete · Your newsletter draft is open for review. Nothing was sent.")
    end
  end

  defp guide_title(state, count) do
    case state.index do
      0 ->
        gettext("Step 1 of 2 · Open Contacts through the Manage menu.")

      1 ->
        gettext("Step 2 of 2 · Choose %{area} in Named areas.",
          area: Guide.area_label(state.plan)
        )

      _ ->
        gettext("Complete · %{count} contacts match this area.", count: count || 0)
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
    budget_status = Assistant.budget_status(usage, mode)

    cond do
      budget_status == :allocation_unavailable ->
        gettext("Assistant credit allocation is not ready. Your draft is retained.")

      not Assistant.visible?(scope) ->
        readiness_message(Assistant.readiness())

      budget_status == :usage_unavailable ->
        gettext("Usage limits are temporarily unavailable. Your draft is retained.")

      budget_status == :tokens_insufficient ->
        gettext(
          "Your remaining token allowance cannot cover another request. Your draft is retained."
        )

      budget_status == :credit_insufficient ->
        gettext(
          "Available credit cannot cover the USD %{amount} request reservation. Your draft is retained.",
          amount: usd(usage.max_turn_cost_micros, Gettext.get_locale(PauseAiCaWeb.Gettext))
        )

      budget_status == :mode_unavailable ->
        gettext("Choose an available mode. Higher modes are paused near a usage limit.")

      true ->
        nil
    end
  end

  defp readiness_message(checks) do
    if :operator_alerts in checks or :audit_anchor in checks do
      gettext(
        "Send is paused while the assistant’s monitoring connection recovers. Your message is retained. Availability is checked automatically."
      )
    else
      gettext(
        "Send is paused while the assistant’s configuration checks recover. Your message is retained. Availability is checked automatically."
      )
    end
  end

  defp draft_key(%{current_scope: %Scope{user: %{id: actor}}, conversation: conversation})
       when is_binary(conversation),
       do: "v1:#{actor}:#{conversation}"

  defp draft_key(_), do: nil

  defp usage_summary(nil, _admin), do: nil

  defp usage_summary(usage, false) do
    gettext("%{remaining} / %{limit} tokens remaining today",
      remaining: usage.remaining_tokens,
      limit: usage.limit
    )
  end

  defp usage_summary(usage, true) do
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
      pilot_summary(usage, locale) <>
      " · " <> gettext("Budget resets on %{date} at 00:00 UTC", date: date)
  end

  defp pilot_summary(%{pilot: pilot}, locale) when is_map(pilot) do
    " · " <>
      gettext("All-provider pilot · USD %{remaining} / %{limit} remaining through %{date} UTC",
        remaining: usd(pilot.remaining_micros, locale),
        limit: usd(pilot.limit_micros, locale),
        date: Calendar.strftime(pilot.expires_at, "%Y-%m-%d %H:%M")
      )
  end

  defp pilot_summary(_, _), do: ""

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
      draft_key={draft_key(assigns)}
      messages={@messages}
      pending={@pending}
      error={@error || @availability_error || @guide_error}
      error_href={
        cond do
          @admin_controls && @error && @pending_request_id ->
            "/admin/assistant/activity/requests/#{@pending_request_id}?locale=#{@locale}"

          @admin_controls && @availability_error ->
            "/admin/assistant?locale=#{@locale}"

          true ->
            nil
        end
      }
      guided_available={@guide_available}
      guided_mode={@guide_mode}
      allow_new={true}
      usage_summary={usage_summary(@usage, @admin_controls)}
      usage_percent={@usage && div(@usage.remaining_tokens * 100, max(@usage.limit, 1))}
      quota_exhausted={not is_nil(@availability_error)}
      labels={
        %{
          "fast" => gettext("Fast"),
          "normal" => gettext("Normal"),
          "high" => gettext("High"),
          assistant: gettext("Assistant"),
          launcher_move:
            gettext(
              "Drag this button to move it, or use the arrow keys when focused. Home resets its position."
            ),
          guided_mode: gettext("Guided mode"),
          new_conversation: gettext("New conversation"),
          move: gettext("Move assistant with arrow keys"),
          send: gettext("Send"),
          close: gettext("Close assistant"),
          minimize: gettext("Minimize assistant"),
          expand: gettext("Expand assistant"),
          mode: gettext("Mode"),
          budget_limited: gettext("Unavailable"),
          usage_details: gettext("Daily tokens"),
          usage_remaining: gettext("Daily token allowance remaining"),
          message: gettext("Message"),
          working: gettext("Working…"),
          error_details:
            if(@error && @pending_request_id,
              do: gettext("Review details"),
              else: gettext("Assistant settings")
            ),
          placeholder: gettext("How can I help?")
        }
      }
    />
    <details
      :if={@guide_state && @guide_state.plan["journey"] == "crm.vancouver_workflow"}
      id="vancouver-guide-reference"
      class="mx-auto max-w-4xl rounded-lg border border-base-300 bg-base-100 p-4"
    >
      <summary class="cursor-pointer font-semibold">
        {gettext("Vancouver postal-area reference · 31 candidates")}
      </summary>
      <p class="mt-3">
        {Enum.join(PauseAiCa.Assistant.CanadianReferences.vancouver()["candidate_fsas"], ", ")}
      </p>
      <p class="mt-3">
        {gettext(
          "These postal-locality candidates do not establish city boundaries. V6T includes UBC; V6S and V6N need boundary review. This guide selects recorded city Vancouver, without adding these FSAs to the audience."
        )}
      </p>
      <p class="mt-3">
        <a
          class="underline"
          href="https://download.geonames.org/export/zip/"
          target="_blank"
          rel="noopener noreferrer"
        >{gettext("GeoNames public source · pinned 9 November 2026")}</a>
      </p>
    </details>
    <PhoenixAgentAssistant.GuidedModeComponents.wizard
      id="site-assistant-guide"
      reserve_scroll={@guide_state && @guide_state.plan["journey"] == "crm.vancouver_workflow"}
      return_focus_id="site-assistant-launcher"
      observer_target_id={
        if @guide_state && @guide_state.plan["journey"] == "crm.vancouver_workflow" &&
             @guide_state.index >= 2, do: "assistant-guided-workspace", else: "crm-directory"
      }
      state={@guide_state}
      title={guide_title(@guide_state, @guide_count)}
      error={@guide_error}
      labels={
        %{
          heading: gettext("Guided mode"),
          next: gettext("Next"),
          back: gettext("Back"),
          exit: gettext("Exit")
        }
      }
    />
    """
  end
end
