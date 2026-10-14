defmodule PauseAiCa.Newsletters.Message do
  @moduledoc "The same newsletter envelope for delivery and clearly labelled previews. No delivery or token creation."
  alias PauseAiCaWeb.{Emails.Layout, Site}
  @example_unsubscribe "https://example.org/newsletter-unsubscribe-preview"

  def render(subject, source, unsubscribe_url, blocks \\ [], locale \\ nil) do
    Layout.render(subject, if(locale == "fr", do: subject, else: ""), blocks, nil,
      locale: locale,
      font_family: "Arial,Helvetica,sans-serif",
      heading_font_family: "Arial,Helvetica,sans-serif",
      width: 680,
      body_html: PauseAiCa.Mail.Render.html(source),
      body_text: source,
      footer: {
        "You are receiving a PauseAI Canada update. You can unsubscribe using the link below.",
        "Vous recevez des nouvelles de PauseIA Canada. Vous pouvez vous désabonner avec le lien ci-dessous."
      },
      footer_links:
        [
          {case locale do
             "en" -> "Unsubscribe"
             "fr" -> "Se désabonner"
             _ -> "Unsubscribe · Se désabonner"
           end, unsubscribe_url}
        ] ++ subscription_links(locale)
    )
  end

  defp subscription_links("en"),
    do: [{"Subscribe · English", Site.url("en", "/en/participate?intent=newsletter")}]

  defp subscription_links("fr"),
    do: [{"S’inscrire · Français", Site.url("fr", "/fr/participer?intent=newsletter")}]

  defp subscription_links(_), do: subscription_links("en") ++ subscription_links("fr")

  def preview(subject, source, locale \\ nil) do
    {html, _text} =
      render(
        subject,
        source,
        @example_unsubscribe,
        [
          {"Preview: the unsubscribe link is an example. Delivered emails use a personal link.",
           "Aperçu : le lien de désabonnement est un exemple. Chaque courriel envoyé contient un lien personnel."}
        ],
        locale
      )

    html
  end
end
