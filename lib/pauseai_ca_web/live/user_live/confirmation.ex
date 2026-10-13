defmodule PauseAiCaWeb.UserLive.Confirmation do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>
            {if @participation_request,
              do: gettext("Confirm your choices"),
              else: gettext("Welcome %{email}", email: @user.email)}
          </.header>
        </div>

        <div :if={@participation_request} class="mt-5">
          <ul class="mt-3 list-disc space-y-2 pl-5">
            <li>{gettext("Save and record my actions with an account.")}</li>
            <li :if={@participation_request.newsletter}>{gettext("PauseAI Canada newsletter")}</li>
            <li :if={@participation_request.local_kind}>
              {if @participation_request.local_kind == "help",
                do: gettext("Offer of help"),
                else: gettext("Local waitlist")} · {@participation_request.city ||
                @participation_request.fsa}
            </li>
          </ul>
          <.form
            for={@form}
            id="participation-confirmation-form"
            phx-submit="submit"
            action={~p"/users/log-in"}
            phx-trigger-action={@trigger_submit}
            class="mt-5"
          >
            <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
            <.continuation_fields continuation={@continuation} />
            <button
              type="submit"
              phx-disable-with={gettext("Confirming…")}
              class="w-full rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold"
            >{gettext("Confirm and continue")}</button>
          </.form>
        </div>

        <.form
          :if={!@participation_request && !@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.continuation_fields continuation={@continuation} />
          <.button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with="Confirming..."
            class="btn btn-primary w-full"
          >
            {gettext("Confirm and stay logged in")}
          </.button>
          <.button phx-disable-with="Confirming..." class="btn btn-primary btn-soft w-full mt-2">
            {gettext("Confirm and log in only this time")}
          </.button>
        </.form>

        <.form
          :if={!@participation_request && @user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.continuation_fields continuation={@continuation} />
          <%= if @current_scope do %>
            <.button phx-disable-with="Logging in..." class="btn btn-primary w-full">
              {gettext("Log in")}
            </.button>
          <% else %>
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="Logging in..."
              class="btn btn-primary w-full"
            >
              {gettext("Keep me logged in on this device")}
            </.button>
            <.button phx-disable-with="Logging in..." class="btn btn-primary btn-soft w-full mt-2">
              {gettext("Log me in only this time")}
            </.button>
          <% end %>
        </.form>

        <p :if={!@participation_request && !@user.confirmed_at} class="alert alert-outline mt-8">
          Tip: If you prefer passwords, you can enable them in the user settings.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token} = params, _session, socket) do
    locale = PauseAiCaWeb.Site.locale(params, socket)
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    socket = assign(socket, :locale, locale)

    if user = Accounts.get_user_by_magic_link_token(token) do
      context = PauseAiCa.Accounts.Onboarding.restore(params["flow"], user)

      participation =
        if id = context["participation_id"],
          do: PauseAiCa.Repo.get(PauseAiCa.Participation.Request, id)

      participation =
        if participation && participation.user_id == user.id && participation.state == "pending",
          do: participation

      form = to_form(%{"token" => token}, as: "user")

      {:ok,
       assign(socket,
         user: user,
         participation_request: participation,
         form: form,
         continuation: Map.take(params, ~w(flow bookmark risk pause coordination)),
         trigger_submit: false
       ), temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(
         :error,
         "This sign-in link is invalid or has expired. Request a new one below. · Ce lien de connexion est invalide ou a expiré. Demandez-en un nouveau ci-dessous."
       )
       |> push_navigate(to: ~p"/users/log-in?#{Map.take(params, ~w(flow locale))}")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end

  attr :continuation, :map, required: true

  defp continuation_fields(assigns) do
    ~H"""
    <input
      :for={{name, value} <- @continuation}
      type="hidden"
      name={"user[#{name}]"}
      value={value}
    />
    """
  end
end
