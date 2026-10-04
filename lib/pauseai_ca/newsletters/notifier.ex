defmodule PauseAiCa.Newsletters.Notifier do
  @moduledoc "Consumer-owned confirmation message builder; delivery uses the existing guarded Mailer."
  import Swoosh.Email
  alias PauseAiCa.Newsletters.Subscription
  alias PauseAiCaWeb.Emails.Layout

  @doc "Builds only the requested confirmation. A URL builder is trusted application code, never public input."
  def confirmation(%Subscription{state: "pending"} = subscription, url) when is_binary(url) do
    {html, text} =
      Layout.render(
        "Confirm newsletter signup",
        "Confirmer l’inscription à l’infolettre",
        [
          {"You requested PauseAI Canada newsletter updates. Confirm this address to complete your signup.",
           "Vous avez demandé à recevoir l’infolettre de PauseIA Canada. Confirmez cette adresse pour terminer votre inscription."},
          {"This link expires in 24 hours. If you did not request these updates, ignore this message.",
           "Ce lien expire dans 24 heures. Si vous n’avez pas demandé ces nouvelles, ignorez ce message."}
        ],
        {"Confirm signup", "Confirmer l’inscription", url}
      )

    new()
    |> to(subscription.email)
    |> from(
      Application.get_env(:pauseai_ca, :campaign_sender, {"PauseAI Canada", "info@pauseai.ca"})
    )
    |> subject("Confirm newsletter signup · Confirmer l’inscription à l’infolettre")
    |> html_body(html)
    |> text_body(text)
  end
end
