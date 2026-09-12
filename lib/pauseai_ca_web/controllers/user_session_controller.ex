defmodule PauseAiCaWeb.UserSessionController do
  use PauseAiCaWeb, :controller

  alias PauseAiCa.{Accounts, Engagement}
  alias PauseAiCa.Accounts.Onboarding
  alias PauseAiCaWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(
      conn,
      params,
      "You're in — your email is confirmed. · Vous êtes connecté·e — votre adresse courriel est confirmée."
    )
  end

  def create(conn, params) do
    create(conn, params, "Welcome back. · Bon retour.")
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    before = Accounts.get_user_by_magic_link_token(token)

    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        UserAuth.disconnect_sessions(tokens_to_disconnect)
        context = Onboarding.restore(user_params["flow"], user)

        conn =
          if context == %{},
            do: conn,
            else: put_session(conn, :user_return_to, context["return_to"])

        if context == %{},
          do: save_continuation(conn, user, user_params),
          else: Onboarding.apply_context(user, context, conn.assigns.learning_visitor_id)

        conn
        |> put_flash(:info, info)
        |> confirmation_metric(before, user)
        |> UserAuth.log_in_user(user, user_params)

      _ ->
        conn
        |> put_flash(
          :error,
          "This sign-in link is invalid or has expired. Request a new one below. · Ce lien de connexion est invalide ou a expiré. Demandez-en un nouveau ci-dessous."
        )
        |> redirect(to: ~p"/users/log-in?#{Map.take(user_params, ~w(flow))}")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(
        :error,
        "That email and password do not match. · Cette adresse courriel et ce mot de passe ne correspondent pas."
      )
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log-in")
    end
  end

  defp save_continuation(conn, user, params) do
    if params["bookmark"] do
      Accounts.save_resource(user, params["bookmark"])

      Engagement.record_learning_signal(
        conn.assigns.learning_visitor_id,
        user,
        "resource_bookmarked",
        params["bookmark"]
      )
    end

    answers = Map.take(params, ~w(risk pause coordination))
    if answers != %{}, do: Accounts.save_belief_answers(user, answers)
  end

  defp confirmation_metric(conn, %{confirmed_at: nil}, user) do
    put_flash(
      conn,
      :signup_metric,
      Jason.encode!(%{event: "account_confirmed", source: user.signup_entry_point || "unknown"})
    )
  end

  defp confirmation_metric(conn, _before, _user), do: conn

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Your password is updated. · Votre mot de passe a été mis à jour.")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "You're signed out. · Vous êtes déconnecté·e.")
    |> UserAuth.log_out_user()
  end
end
