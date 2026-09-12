defmodule PauseAiCaWeb.UserLive.Registration do
  use PauseAiCaWeb, :live_view
  alias PauseAiCaWeb.UserLive.Login

  @impl true
  def render(assigns), do: Login.render(assigns)

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: PauseAiCaWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(params, session, socket) do
    {:ok, socket} = Login.mount(params, session, socket)

    {:ok,
     assign(socket,
       form_id: "registration_form",
       submit_event: "save",
       auth_title: gettext("Create an account")
     )}
  end

  @impl true
  def handle_event("save", params, socket), do: Login.handle_event("submit_magic", params, socket)
  def handle_event(event, params, socket), do: Login.handle_event(event, params, socket)
end
