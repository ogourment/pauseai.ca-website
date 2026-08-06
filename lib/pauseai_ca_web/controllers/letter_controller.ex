defmodule PauseAiCaWeb.LetterController do
  @moduledoc """
  Releases a letter that was waiting for its sender to confirm the address.

  A GET is the wrong verb for something with an effect, but it is the only verb
  a link in an email can produce, and the token is single-use and short-lived.
  """

  use PauseAiCaWeb, :controller

  alias PauseAiCa.Audit
  alias PauseAiCa.Campaigns.Confirmations

  def confirm(conn, %{"token" => token}) do
    case Confirmations.release(token) do
      {:ok, %{locale: locale}} ->
        Audit.event(:letter_released, %{locale: locale})

        conn
        |> put_flash(:info, sent_message(locale))
        |> redirect(to: campaign_path(locale))

      {:error, reason} ->
        Audit.event(:letter_release_failed, %{reason: reason})

        conn
        |> put_flash(:error, failed_message(locale_from(conn)))
        |> redirect(to: campaign_path(locale_from(conn)))
    end
  end

  defp campaign_path("fr"), do: ~p"/fr/tir-de-semonce"
  defp campaign_path(_locale), do: ~p"/en/warning-shot"

  defp locale_from(conn) do
    if String.starts_with?(conn.request_path, "/fr"), do: "fr", else: "en"
  end

  defp sent_message(_locale),
    do: gettext("Your letter is on its way. Thank you — offices often reply within a few days.")

  defp failed_message(_locale),
    do: gettext("That link is no longer valid. Links expire after 24 hours and work only once.")
end
