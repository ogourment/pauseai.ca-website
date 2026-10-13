defmodule PauseAiCaWeb.UserLive.Registration do
  use PauseAiCaWeb, :live_view
  alias PauseAiCaWeb.ParticipationLive

  @impl true
  def render(assigns), do: ParticipationLive.render(assigns)

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: PauseAiCaWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(params, session, socket) do
    {:ok, socket} = ParticipationLive.mount(Map.put(params, "intent", "account"), session, socket)
    {:ok, assign(socket, registration: true)}
  end
end
