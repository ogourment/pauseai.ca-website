defmodule PauseAiCa.Newsletters.Message do
  @moduledoc "The same newsletter envelope for delivery and clearly labelled previews. No delivery or token creation."
  alias PauseAiCaWeb.{Emails.Layout, Site}
  @example_unsubscribe "https://example.org/newsletter-unsubscribe-preview"

  def render(subject, source, unsubscribe_url, blocks \\ []) do
    Layout.render(subject, "", blocks, {"Unsubscribe", "Se désabonner", unsubscribe_url},
      body_html: PauseAiCa.Mail.Render.html(source),
      body_text: source,
      footer: {
        "You are receiving a PauseAI Canada update. You can unsubscribe using the link above.",
        "Vous recevez des nouvelles de PauseIA Canada. Vous pouvez vous désabonner avec le lien ci-dessus."
      },
      footer_links: [
        {"Subscribe · English", Site.url("en", "/en/learn#newsletter-heading")},
        {"S’inscrire · Français", Site.url("fr", "/fr/comprendre#newsletter-heading")}
      ]
    )
  end

  def preview(subject, source) do
    {html, _text} =
      render(subject, source, @example_unsubscribe, [
        {"Preview: the unsubscribe link is an example. Delivered emails use a personal link.",
         "Aperçu : le lien de désabonnement est un exemple. Chaque courriel envoyé contient un lien personnel."}
      ])

    html
  end
end
