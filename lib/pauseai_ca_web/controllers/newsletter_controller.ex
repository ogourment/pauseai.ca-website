defmodule PauseAiCaWeb.NewsletterController do
  use PauseAiCaWeb, :controller
  alias PauseAiCa.Newsletters

  def show_confirm(conn, %{"token" => token}), do: show(conn, token, :confirm)

  def show_confirm(conn, _), do: show(conn, nil, :confirm)
  def show_withdraw(conn, %{"token" => token}), do: show(conn, token, :withdraw)
  def show_withdraw(conn, _), do: show(conn, nil, :withdraw)
  def confirm(conn, %{"token" => token}), do: apply_action(conn, token, :confirm)
  def confirm(conn, _), do: apply_action(conn, nil, :confirm)
  def withdraw(conn, %{"token" => token}), do: apply_action(conn, token, :withdraw)
  def withdraw(conn, _), do: apply_action(conn, nil, :withdraw)

  defp show(conn, token, action) do
    case Newsletters.capability(token, action) do
      {:ok, %{locale: locale}} -> page(conn, token, action, locale, :ready)
      {:error, _} -> page(conn, nil, action, locale(conn), :invalid)
    end
  end

  defp apply_action(conn, token, action) do
    result =
      case action do
        :confirm -> Newsletters.confirm(token)
        :withdraw -> Newsletters.withdraw(token)
      end

    case result do
      {:ok, subscription} -> page(conn, nil, action, subscription.locale, :done)
      {:error, _} -> page(conn, nil, action, locale(conn), :invalid)
    end
  end

  defp page(conn, token, action, locale, state) do
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> assign(:locale, locale)
    |> render(:action,
      token: token,
      action: action,
      state: state,
      page_title: gettext("Newsletter")
    )
  end

  defp locale(conn), do: if(conn.params["locale"] == "fr", do: "fr", else: "en")
end
