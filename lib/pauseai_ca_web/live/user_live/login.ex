defmodule PauseAiCaWeb.UserLive.Login do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.panel title_en="Sign in" title_fr="Se connecter">
        <:subtitle>
          <%= if @current_scope do %>
            <.bilingual
              en="Confirm it is you before changing your account."
              fr="Confirmez votre identité avant de modifier votre compte."
            />
          <% else %>
            <.bilingual
              en="We email you a link. No password to invent or forget."
              fr="Nous vous envoyons un lien par courriel. Aucun mot de passe à inventer ni à oublier."
            />
          <% end %>
        </:subtitle>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/users/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_scope}
            field={f[:email]}
            type="email"
            label="Email · Courriel"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <button
            type="submit"
            class="mt-2 w-full rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 transition hover:bg-brand-strong"
          >
            Email me a link · Envoyez-moi un lien
          </button>
        </.form>

        <p :if={!@current_scope} class="mt-6 text-sm leading-6 text-stone-500">
          Entering your address above makes an account if you do not have one, or you can
          <.link
            navigate={~p"/users/register"}
            class="font-semibold text-stone-800 underline decoration-brand decoration-2 underline-offset-4"
          >Register</.link>
          first.<br /> Entrer votre adresse ci-dessus crée un compte si vous n'en avez pas.
        </p>

        <details class="mt-6 border-t border-stone-200 pt-4">
          <summary class="cursor-pointer text-sm font-semibold text-stone-600">
            Prefer a password? · Vous préférez un mot de passe?
          </summary>

          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={~p"/users/log-in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
            class="mt-4"
          >
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label="Email · Courriel"
              autocomplete="username"
              spellcheck="false"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password · Mot de passe"
              autocomplete="current-password"
              spellcheck="false"
            />
            <button
              type="submit"
              name={@form[:remember_me].name}
              value="true"
              class="mt-2 w-full rounded-full border-2 border-stone-300 px-6 py-3 font-heading font-bold text-stone-800 transition hover:border-brand"
            >
              Sign in · Se connecter
            </button>
          </.form>
        </details>
      </.panel>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If that address has an account, a secure sign-in link is on its way. · Si cette adresse correspond à un compte, un lien de connexion sécurisé est en route."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end
end
