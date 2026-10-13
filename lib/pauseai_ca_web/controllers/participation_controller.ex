defmodule PauseAiCaWeb.ParticipationController do
  use PauseAiCaWeb, :controller
  alias PauseAiCa.Participation
  def show_confirm(conn, params), do: show(conn, params["token"], :confirm)
  def show_withdraw(conn, params), do: show(conn, params["token"], :withdraw)
  def confirm(conn, params), do: apply_choice(conn, params["token"], :confirm)
  def withdraw(conn, params), do: apply_choice(conn, params["token"], :withdraw)

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
      action: action,
      state: state,
      page_title: gettext("Your choices")
    )
  end
end
