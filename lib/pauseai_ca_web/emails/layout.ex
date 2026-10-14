defmodule PauseAiCaWeb.Emails.Layout do
  @moduledoc "PauseAI branding/copy adapter for the shared mail envelope; no delivery or persistence."
  def render(title_en, title_fr, blocks, action \\ nil, opts \\ []) do
    defaults = [
      brand_name: "PauseAI Canada",
      identity_text: "pauseai.ca · info@pauseai.ca",
      brand_color: "#f68b1e",
      ink_color: "#1c1917",
      background_color: "#f8f5ed",
      font_family: "Georgia,'Times New Roman',serif",
      heading_font_family: "Impact,'Helvetica Neue',Arial,sans-serif",
      action_font_family: "Impact,'Helvetica Neue',Arial,sans-serif",
      width: 560,
      footer_link_color: "#854d0e",
      footer:
        {"You are receiving this because someone asked to sign in with this address.",
         "Vous recevez ce message parce qu'une connexion a été demandée avec cette adresse."}
    ]

    PhoenixMailWorkflow.Layout.render(
      title_en,
      title_fr,
      blocks,
      action,
      Keyword.merge(defaults, opts)
    )
  end

  def deliverability_notice do
    {"Did this land in spam or promotions? Please move it to your inbox and mark it \"Not spam\". It takes a second, and it is how we stay out of the spam folder for everyone else.",
     "Ce message est-il arrivé dans les indésirables ou les promotions? Déplacez-le vers votre boîte de réception et marquez-le « Non indésirable ». Cela prend une seconde, et c'est ainsi que nous évitons le dossier spam pour tout le monde."}
  end
end
