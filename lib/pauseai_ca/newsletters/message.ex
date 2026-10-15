defmodule PauseAiCa.Newsletters.Message do
  @moduledoc "The same newsletter envelope for delivery and clearly labelled previews. No delivery or token creation."
  alias PauseAiCaWeb.Site

  def render(subject, source, unsubscribe_url, blocks \\ [], locale \\ nil) do
    PhoenixMailWorkflow.Newsletter.render(
      subject,
      source,
      unsubscribe_url,
      Keyword.put(options(locale), :blocks, blocks)
    )
  end

  def preview(subject, source, locale \\ nil) do
    PhoenixMailWorkflow.Newsletter.preview(subject, source, options(locale))
  end

  defp options(locale) do
    [
      brand_name: "PauseAI Canada",
      identity_text: "pauseai.ca · info@pauseai.ca",
      logo: %{
        src: Site.url("en", "/images/pauseai-canada-logo.png"),
        alt: "PauseAI Canada",
        width: 160,
        href: Site.url(locale || "en", "/#{locale || "en"}")
      },
      brand_color: "#f68b1e",
      ink_color: "#1c1917",
      background_color: "#f8f5ed",
      footer_link_color: "#854d0e",
      locale: locale,
      render_body: &PauseAiCa.Mail.Render.html/1,
      footer:
        {"You are receiving a PauseAI Canada update. You can unsubscribe using the link below.",
         "Vous recevez des nouvelles de PauseIA Canada. Vous pouvez vous désabonner avec le lien ci-dessous."},
      unsubscribe_labels: %{
        "en" => "Unsubscribe",
        "fr" => "Se désabonner",
        "unknown" => "Unsubscribe · Se désabonner"
      },
      subscription_links: subscription_links(locale)
    ]
  end

  defp subscription_links("en"),
    do: [{"Subscribe · English", Site.url("en", "/en/participate?intent=newsletter")}]

  defp subscription_links("fr"),
    do: [{"S’inscrire · Français", Site.url("fr", "/fr/participer?intent=newsletter")}]

  defp subscription_links(_), do: subscription_links("en") ++ subscription_links("fr")
end
