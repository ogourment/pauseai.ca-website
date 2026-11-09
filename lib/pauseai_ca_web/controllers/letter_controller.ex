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
    context = Confirmations.context(token)

    locale =
      if context && context.locale in ["en", "fr"], do: context.locale, else: locale_from(conn)

    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    case Confirmations.release(token) do
      {:ok, %{locale: locale}} ->
        Audit.event(:letter_released, %{locale: locale})

        conn
        |> put_flash(:info, sent_message(locale))
        |> put_flash(:dev_mailbox, true)
        |> redirect(to: campaign_path(locale))

      {:error, :delivery_unknown} ->
        Audit.event(:letter_release_failed, %{reason: :delivery_unknown})
        reference = if context, do: context.intent_reference

        message =
          if reference do
            gettext(
              "Delivery is awaiting verification. Keep this draft and contact us with reference %{reference} before sending again.",
              reference: reference
            )
          else
            gettext(
              "Delivery is awaiting verification. Keep this draft and contact us before sending it again."
            )
          end

        conn |> put_flash(:error, message) |> redirect(to: campaign_path(locale))

      {:error, :delivery_failed} ->
        Audit.event(:letter_release_failed, %{reason: :delivery_failed})

        conn
        |> put_flash(:error, gettext("Sending failed. Try again, or use your email app."))
        |> redirect(to: campaign_path(locale))

      {:error, reason} ->
        Audit.event(:letter_release_failed, %{reason: reason})

        conn
        |> put_flash(:error, failed_message(locale))
        |> redirect(to: campaign_path(locale))
    end
  end

  defp campaign_path("fr"), do: ~p"/fr/contacter-votre-depute"
  defp campaign_path(_locale), do: ~p"/en/contact-your-mp"

  defp locale_from(conn) do
    if String.starts_with?(conn.request_path, "/fr"), do: "fr", else: "en"
  end

  defp sent_message(_locale),
    do: gettext("Your letter is on its way. Thank you — offices often reply within a few days.")

  defp failed_message(_locale),
    do: gettext("That link is no longer valid. Links expire after 24 hours and work only once.")
end
