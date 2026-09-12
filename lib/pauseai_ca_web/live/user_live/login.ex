defmodule PauseAiCaWeb.UserLive.Login do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Accounts
  alias PauseAiCa.Accounts.{Onboarding, User}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale}>
      <.panel title_en={@auth_title} title_fr={@auth_title}>
        <:subtitle>
          <%= if @current_scope do %>
            {gettext("Confirm it is you before changing your account.")}
          <% else %>
            {gettext(
              "Keep your answers, saved resources and progress when you return. We email you a secure link; no password is required."
            )}
          <% end %>
        </:subtitle>
        <.form
          for={@form}
          id={@form_id}
          action={~p"/users/log-in"}
          phx-submit={@submit_event}
          phx-change="validate"
        >
          <.input
            id={"#{@form_id}_email"}
            readonly={!!@current_scope}
            field={@form[:email]}
            aria-invalid={to_string(@form[:email].errors != [])}
            aria-describedby={"#{@form_id}_email_validation"}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <p id={"#{@form_id}_email_validation"} aria-live="polite" class="sr-only">
            {Enum.map_join(@form[:email].errors, " ", &translate_error/1)}
          </p>
          <button
            type="submit"
            phx-disable-with={gettext("Sending…")}
            class="mt-2 w-full rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 transition hover:bg-brand-strong focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-brand"
          >
            {gettext("Email me a secure link")}
          </button>
        </.form>
        <p
          :if={@pending?}
          id="account-email-pending"
          role="status"
          class="mt-5 rounded-xl bg-stone-100 p-4 text-sm"
        >
          {gettext(
            "Check your email for the next step. You can keep browsing while you wait, or request another link below."
          )}
        </p>
        <p
          :if={@delivery_error?}
          id="account-email-error"
          role="alert"
          class="mt-5 text-sm text-red-800"
        >
          {gettext("We could not send your link. Your progress is still available. Please try again.")}
        </p>
        <p :if={!@current_scope} class="mt-6 text-sm leading-6 text-stone-600">
          {gettext(
            "A new email creates an account awaiting confirmation. An existing email signs you in. Your address is never sold or shared."
          )}
        </p>
        <.link
          :if={!@current_scope}
          id="continue-browsing"
          href={if(@locale == "fr", do: ~p"/fr", else: ~p"/en")}
          class="mt-4 inline-block font-semibold underline decoration-brand decoration-2 underline-offset-4"
        >
          {gettext("Continue browsing")}
        </.link>
        <p :if={@form_id == "registration_form"} class="mt-4 text-sm">
          <.link navigate={~p"/users/log-in?#{%{locale: @locale}}"} class="underline">{gettext(
            "Sign in"
          )}</.link>
        </p>
        <details class="mt-6 border-t border-stone-200 pt-4">
          <summary class="cursor-pointer text-sm font-semibold text-stone-600">
            {gettext("Prefer a password?")}
          </summary>
          <.form
            for={@form}
            id="login_form_password"
            action={~p"/users/log-in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
            class="mt-4"
          >
            <.input
              id="login_form_password_email"
              readonly={!!@current_scope}
              field={@form[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label={gettext("Password")}
              autocomplete="current-password"
            />
            <button
              type="submit"
              name={@form[:remember_me].name}
              value="true"
              class="mt-2 w-full rounded-full border-2 border-stone-300 px-6 py-3 font-heading font-bold"
            >{gettext("Sign in")}</button>
          </.form>
        </details>
      </.panel>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, session, socket) do
    original = Onboarding.context(params, session["learning_visitor_id"])
    decoded = Onboarding.decode(params["flow"])
    context = if decoded == %{}, do: original, else: decoded
    locale = context["locale"] || "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    changeset = Accounts.change_user_email(%User{}, %{email: email}, validate_unique: false)

    {:ok,
     assign(socket,
       form: to_form(changeset, as: "user"),
       trigger_submit: false,
       context: context,
       locale: locale,
       form_id: "login_form_magic",
       submit_event: "submit_magic",
       auth_title: gettext("Sign in / Sign up"),
       pending?: false,
       delivery_error?: false
     )}
  end

  @impl true
  def handle_event("submit_password", _params, socket),
    do: {:noreply, assign(socket, :trigger_submit, true)}

  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_email(%User{}, params, validate_unique: false)
    {:noreply, assign(socket, form: to_form(Map.put(changeset, :action, :validate), as: "user"))}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if socket.assigns.current_scope do
      # Reauthentication must never become signup or trust a forged readonly email.
      user = socket.assigns.current_scope.user

      case Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}")) do
        {:ok, _} -> {:noreply, assign(socket, pending?: true, delivery_error?: false)}
        {:error, _} -> {:noreply, assign(socket, delivery_error?: true)}
      end
    else
      case Onboarding.request(email, socket.assigns.context, fn token, flow ->
             url(~p"/users/log-in/#{token}?#{%{flow: flow, locale: socket.assigns.locale}}")
           end) do
        {:ok, user, created?, flow} ->
          {:noreply,
           socket
           |> creation_metric(user, created?)
           |> assign(
             pending?: true,
             delivery_error?: false,
             context: Onboarding.restore(flow, user)
           )}

        {:error, :delivery, user, created?, flow} ->
          {:noreply,
           socket
           |> creation_metric(user, created?)
           |> assign(
             delivery_error?: true,
             pending?: false,
             context: Onboarding.restore(flow, user)
           )}

        {:error, :continuation} ->
          {:noreply, assign(socket, delivery_error?: true, pending?: false)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           assign(socket,
             form: to_form(Map.put(changeset, :action, :insert), as: "user"),
             pending?: false
           )}
      end
    end
  end

  defp creation_metric(socket, user, true),
    do:
      push_event(socket, "signup-metric", %{
        event: "sign_up",
        source: user.signup_entry_point || "unknown"
      })

  defp creation_metric(socket, _user, false), do: socket
end
