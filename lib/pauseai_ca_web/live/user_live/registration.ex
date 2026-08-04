defmodule PauseAiCaWeb.UserLive.Registration do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Accounts
  alias PauseAiCa.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.panel title_en="Create an account" title_fr="Créer un compte">
        <:subtitle>
          <.bilingual
            en="An account keeps a private record of what you have done, and lets your letters go in one click."
            fr="Un compte conserve un registre privé de vos actions et permet à vos lettres de partir en un clic."
          />
        </:subtitle>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label="Email · Courriel"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <button
            type="submit"
            phx-disable-with="Creating account… · Création…"
            class="mt-2 w-full rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 transition hover:bg-brand-strong"
          >
            Create account · Créer le compte
          </button>
        </.form>

        <p class="mt-6 text-sm leading-6 text-stone-500">
          Your address is used to sign you in and is never sold or shared.<br />
          Votre adresse sert à vous connecter; elle n'est jamais vendue ni partagée.
        </p>

        <p class="mt-4 border-t border-stone-200 pt-4 text-sm leading-6 text-stone-600">
          Already have one?
          <.link
            navigate={~p"/users/log-in"}
            class="font-semibold underline decoration-brand decoration-2 underline-offset-4"
          >
            Sign in
          </.link>
          · Vous en avez déjà un?
          <.link
            navigate={~p"/users/log-in"}
            class="font-semibold underline decoration-brand decoration-2 underline-offset-4"
          >
            Se connecter
          </.link>
        </p>
      </.panel>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: PauseAiCaWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(params, _session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign(:bookmark, params["bookmark"])
     |> assign(:belief_answers, Map.take(params, ~w(risk pause coordination)))
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.get_user_by_email(user_params["email"]) do
      %User{} = user ->
        send_existing_user_login(socket, user)

      nil ->
        register_new_user(socket, user_params)
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_email(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp register_new_user(socket, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        if socket.assigns.bookmark, do: Accounts.save_resource(user, socket.assigns.bookmark)

        if socket.assigns.belief_answers != %{},
          do: Accounts.save_belief_answers(user, socket.assigns.belief_answers)

        {:ok, _} =
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log-in/#{&1}?#{continuation_params(socket)}")
          )

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Check #{user.email} for your secure sign-in link. · Consultez #{user.email} pour obtenir votre lien de connexion sécurisé."
         )
         |> push_navigate(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp send_existing_user_login(socket, user) do
    {:ok, _} =
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}?#{continuation_params(socket)}")
      )

    {:noreply,
     socket
     |> put_flash(
       :info,
       "An account already exists for #{user.email}. Check your email to sign in and continue. · Un compte existe déjà pour #{user.email}. Consultez votre courriel pour vous connecter et continuer."
     )
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp continuation_params(socket) do
    socket.assigns.belief_answers
    |> then(fn params ->
      if socket.assigns.bookmark,
        do: Map.put(params, "bookmark", socket.assigns.bookmark),
        else: params
    end)
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
