defmodule PauseAiCaWeb.UserLive.Settings do
  use PauseAiCaWeb, :live_view

  on_mount {PauseAiCaWeb.UserAuth, :require_sudo_mode}

  alias PauseAiCa.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="account-settings" class="mx-auto max-w-3xl px-5 py-12 sm:py-16">
        <div class="text-center">
          <.header>
            Account settings · Paramètres du compte
            <:subtitle>
              Manage your email and password · Gérez votre adresse courriel et votre mot de passe
            </:subtitle>
          </.header>
        </div>

        <.form
          for={@email_form}
          id="email_form"
          class="mt-10 rounded-3xl border border-stone-200 bg-white p-6 shadow-sm sm:p-8"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <h2 class="mb-5 font-heading text-2xl text-stone-950">Email · Adresse courriel</h2>
          <.input
            field={@email_form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.button variant="primary" phx-disable-with="Changing... · Modification...">
            Change Email · Modifier l'adresse
          </.button>
        </.form>

        <.form
          for={@password_form}
          id="password_form"
          class="mt-8 scroll-mt-24 rounded-3xl border border-stone-200 bg-white p-6 shadow-sm sm:p-8"
          action={~p"/users/update-password"}
          method="post"
          phx-change="validate_password"
          phx-submit="update_password"
          phx-trigger-action={@trigger_submit}
        >
          <h2 class="mb-2 font-heading text-2xl text-stone-950">Password · Mot de passe</h2>
          <p class="mb-5 text-sm leading-6 text-stone-600">
            Use at least 12 characters. · Utilisez au moins 12 caractères.
          </p>
          <input
            name={@password_form[:email].name}
            type="hidden"
            id="hidden_user_email"
            spellcheck="false"
            value={@current_email}
          />
          <.input
            field={@password_form[:password]}
            type="password"
            label="New password · Nouveau mot de passe"
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.input
            field={@password_form[:password_confirmation]}
            type="password"
            label="Confirm new password · Confirmer le nouveau mot de passe"
            autocomplete="new-password"
            spellcheck="false"
          />
          <.button variant="primary" phx-disable-with="Saving... · Enregistrement...">
            Save Password · Enregistrer le mot de passe
          </.button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(
            socket,
            :info,
            "Your email address is updated. · Votre adresse courriel a été mise à jour."
          )

        {:error, _} ->
          put_flash(
            socket,
            :error,
            "This email-change link is invalid or has expired. · Ce lien de changement d'adresse est invalide ou a expiré."
          )
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info =
          "Check the new address for a confirmation link. · Consultez la nouvelle adresse pour obtenir le lien de confirmation."

        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
