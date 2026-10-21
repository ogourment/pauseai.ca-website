defmodule PauseAiCaWeb.ParticipationController do
  use PauseAiCaWeb, :controller
  alias PauseAiCa.Participation
  def show_confirm(conn, params), do: show(conn, params["token"], :confirm)
  def show_withdraw(conn, params), do: show(conn, params["token"], :withdraw)
  def confirm(conn, params), do: apply_choice(conn, params["token"], :confirm)
  def withdraw(conn, params), do: apply_choice(conn, params["token"], :withdraw)

  def edit(conn, params) do
    case Participation.choices_request(params["token"]) do
      {:ok, request} ->
        edit_page(conn, params["token"], request, Participation.Request.changeset(request, %{}))

      _ ->
        page(conn, nil, nil, :confirm, :invalid)
    end
  end

  def save_choices(conn, params) do
    token = params["token"]

    with {:ok, request} <- Participation.choices_request(token) do
      Gettext.put_locale(PauseAiCaWeb.Gettext, request.locale)
      attrs = params["choices"] || %{}
      attrs = Map.put(attrs, "locale", request.locale)
      attrs = Map.put(attrs, "local_kind", if(attrs["local"] == "true", do: attrs["local_kind"]))

      urls = fn
        :account, {token, flow} ->
          PauseAiCaWeb.Site.url(
            request.locale,
            ~p"/users/log-in/#{token}?#{%{flow: flow, locale: request.locale}}"
          )

        action, token ->
          PauseAiCaWeb.Site.url(
            request.locale,
            "/participation/#{action}?" <>
              URI.encode_query(%{token: token, locale: request.locale})
          )
      end

      case Participation.update_choices(token, attrs, urls) do
        {:ok, _} ->
          conn
          |> put_flash(:info, gettext("Check your email to confirm your updated choices."))
          |> redirect(
            to: if(request.locale == "fr", do: ~p"/fr/participer", else: ~p"/en/participate")
          )

        {:error, %Ecto.Changeset{} = changeset} ->
          edit_page(conn, token, request, %{changeset | action: :update})

        _ ->
          page(conn, nil, nil, :confirm, :invalid)
      end
    else
      _ -> page(conn, nil, nil, :confirm, :invalid)
    end
  end

  defp edit_page(conn, token, request, changeset) do
    Gettext.put_locale(PauseAiCaWeb.Gettext, request.locale)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> assign(:locale, request.locale)
    |> render(:edit,
      token: token,
      request: request,
      form:
        Phoenix.Component.to_form(
          Ecto.Changeset.put_change(
            changeset,
            :location,
            Ecto.Changeset.get_field(changeset, :fsa)
          ),
          as: "choices"
        ),
      page_title: gettext("Change my choices")
    )
  end

  def create_account(conn, params) do
    Gettext.put_locale(PauseAiCaWeb.Gettext, if(params["locale"] == "fr", do: "fr", else: "en"))
    # Avoid switching a signed-in visitor into another identity.
    if conn.assigns.current_scope && conn.assigns.current_scope.user do
      redirect(conn, to: ~p"/users/settings")
    else
      case Participation.create_account(params["account_offer"], Map.take(params, ["phone"])) do
        {:ok, user} ->
          conn
          |> put_flash(:info, gettext("Your account is ready."))
          |> put_flash(
            :signup_metric,
            Jason.encode!(%{
              event: "account_confirmed",
              source: user.signup_entry_point || "unknown"
            })
          )
          |> put_session(
            :user_return_to,
            if(conn.params["locale"] == "fr", do: "/fr/tableau-de-bord", else: "/en/dashboard")
          )
          |> PauseAiCaWeb.UserAuth.log_in_user(user)

        {:error, :account_exists} ->
          conn
          |> put_flash(:info, gettext("You already have an account. Sign in to continue."))
          |> redirect(to: ~p"/users/log-in?#{Map.take(params, ["locale"])}")

        {:error, %Ecto.Changeset{} = changeset} ->
          case Participation.account_offer_request(params["account_offer"]) do
            {:ok, request} ->
              conn
              |> assign(
                :phone_form,
                Phoenix.Component.to_form(changeset, as: "account", action: :insert)
              )
              |> page(nil, request, :confirm, :done)

            _ ->
              page(conn, nil, nil, :confirm, :invalid)
          end

        _ ->
          page(conn, nil, nil, :confirm, :invalid)
      end
    end
  end

  defp show(conn, token, action) do
    case Participation.capability(token, action) do
      {:ok, request} -> page(conn, token, request, action, :ready)
      _ -> page(conn, nil, nil, action, :invalid)
    end
  end

  defp apply_choice(conn, token, action) do
    result =
      if action == :confirm, do: Participation.confirm(token), else: Participation.withdraw(token)

    case result do
      {:ok, request} -> page(conn, nil, request, action, :done)
      _ -> page(conn, nil, nil, action, :invalid)
    end
  end

  defp page(conn, token, request, action, state) do
    locale =
      if request,
        do: request.locale,
        else: if(conn.params["locale"] == "fr", do: "fr", else: "en")

    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> assign(:locale, locale)
    |> render(:action,
      token: token,
      request: request,
      account_offer:
        if(state == :done && action == :confirm && is_nil(conn.assigns.current_scope),
          do: Participation.account_offer(request)
        ),
      phone_form: conn.assigns[:phone_form] || Phoenix.Component.to_form(%{}, as: "account"),
      action: action,
      state: state,
      page_title: gettext("Your choices")
    )
  end
end
