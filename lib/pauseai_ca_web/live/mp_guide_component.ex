defmodule PauseAiCaWeb.MPGuideComponent do
  @moduledoc "Supporter MP guidance. Parent supplies server observations; buttons never send a letter."
  use PauseAiCaWeb, :live_component
  alias PauseAiCa.Assistant.MPGuide

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, state: nil, active: false, error: nil, resume_checked: false)}

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if socket.assigns[:resume] and not socket.assigns.resume_checked do
        case MPGuide.start(
               socket.assigns.current_scope,
               socket.assigns.guide_session,
               socket.assigns.locale,
               socket.assigns.uri
             ) do
          {:ok, state} -> assign(socket, state: state, active: true, resume_checked: true)
          _ -> assign(socket, active: true, resume_checked: true)
        end
      else
        socket
      end

    state = socket.assigns.state

    valid_probe =
      not Map.has_key?(assigns, :observation_token) or
        (state && state.token == assigns.observation_token)

    socket = if state && state.token && valid_probe, do: observe(socket), else: socket

    socket =
      if MPGuide.enabled?(),
        do: socket,
        else: assign(socket, state: nil, active: false, error: nil)

    {:ok, socket}
  end

  @impl true
  def handle_event(event, params, socket) do
    if MPGuide.enabled?(),
      do: action(event, params, socket),
      else: {:noreply, assign(socket, state: nil, active: false, error: nil)}
  end

  defp action("mp-guide-start", _, socket) do
    case MPGuide.start(
           socket.assigns.current_scope,
           socket.assigns.guide_session,
           socket.assigns.locale,
           socket.assigns.uri
         ) do
      {:ok, state} -> {:noreply, assign(socket, state: state, active: true, error: nil)}
      _ -> {:noreply, assign(socket, active: true, error: nil)}
    end
  end

  defp action("mp-guide-next", _, %{assigns: %{state: state}} = socket) when is_map(state) do
    case MPGuide.next(
           socket.assigns.current_scope,
           socket.assigns.guide_session,
           socket.assigns.locale,
           socket.assigns.uri,
           socket.assigns.state
         ) do
      {:ok, state, command} ->
        {:noreply,
         socket |> assign(state: state, error: nil) |> push_event("paa:guided-command", command)}

      _ ->
        {:noreply, stopped(socket)}
    end
  end

  defp action("mp-guide-back", _, %{assigns: %{state: state}} = socket) when is_map(state) do
    case MPGuide.back(
           socket.assigns.current_scope,
           socket.assigns.guide_session,
           socket.assigns.locale,
           socket.assigns.uri,
           socket.assigns.state
         ) do
      {:ok, state} ->
        {:noreply,
         socket |> assign(state: state, error: nil) |> push_event("paa:guided-clear", %{})}

      _ ->
        {:noreply, stopped(socket)}
    end
  end

  defp action("mp-guide-exit", _, socket),
    do:
      {:noreply,
       socket
       |> assign(state: nil, active: false, error: nil)
       |> push_event("paa:guided-clear", %{})}

  defp action(
         "mp-guide-failed",
         %{"token" => token},
         %{assigns: %{state: %{token: token}}} = socket
       )
       when is_binary(token), do: {:noreply, stopped(socket)}

  defp action(_, _, socket), do: {:noreply, socket}

  defp observe(socket) do
    case MPGuide.observe(
           socket.assigns.current_scope,
           socket.assigns.guide_session,
           socket.assigns.locale,
           socket.assigns.uri,
           socket.assigns.state,
           socket.assigns.context
         ) do
      {:ok, state} -> assign(socket, state: state, error: nil)
      {:waiting, _} -> socket
      _ -> stopped(socket)
    end
  end

  defp stopped(socket),
    do:
      socket
      |> assign(
        state:
          if(socket.assigns.state,
            do: PhoenixAgentAssistant.GuidedMode.fail(socket.assigns.state),
            else: nil
          ),
        error:
          gettext(
            "This guide stopped because the page or your sign-in changed. Exit and start again."
          )
      )
      |> push_event("paa:guided-clear", %{})

  defp step_title(0),
    do:
      gettext(
        "Enter your name and postal code, then choose Continue to my letter. Your account records an action only after sending."
      )

  defp step_title(1),
    do:
      gettext(
        "Paste and personalize your subject and letter. Replace every remaining placeholder, then choose Next."
      )

  defp step_title(2),
    do:
      gettext(
        "Review the actual MP, sender, subject and letter. You choose the authorization box and Send. The guide cannot send for you."
      )

  defp step_title(_),
    do:
      gettext(
        "Your sent letter is recorded in your account. This confirms the website outcome, not that your MP has read it."
      )

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <button
        :if={MPGuide.enabled?() and !@active}
        type="button"
        id="mp-guide-start"
        phx-click="mp-guide-start"
        phx-target={@myself}
        class="mt-5 rounded-full border-2 border-brand px-5 py-3 font-semibold"
      >{gettext("Guide me through this")}</button>
      <section
        :if={@active and is_nil(@state)}
        id="mp-guide-sign-in"
        class="mt-4 rounded-xl border border-brand bg-brand-wash p-5"
      >
        <p>
          {gettext(
            "Sign in and confirm your email before starting if you want this letter recorded in your account. You can use the MP form without account tracking."
          )}
        </p>
        <.link href={@sign_in_path} class="inline-block py-3 font-semibold underline">{gettext(
          "Sign in"
        )}</.link>
        <button type="button" phx-click="mp-guide-exit" phx-target={@myself} class="ml-4 px-3 py-3">{gettext(
          "Exit"
        )}</button>
      </section>
      <PhoenixAgentAssistant.GuidedModeComponents.wizard
        id="mp-guide"
        state={@state}
        target={@myself}
        event_target_id={@id}
        reserve_scroll={true}
        observer_target_id="mp-letter-flow"
        observer_event="mp-guide-observe"
        event_prefix="mp-guide"
        return_focus_id="mp-guide-start"
        title={if @state, do: step_title(@state.index), else: ""}
        error={@error}
        labels={
          %{
            heading: gettext("MP letter guide"),
            next: gettext("Next"),
            back: gettext("Back"),
            exit: gettext("Exit")
          }
        }
      />
    </div>
    """
  end
end
