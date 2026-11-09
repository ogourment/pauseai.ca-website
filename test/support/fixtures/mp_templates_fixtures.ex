defmodule PauseAiCa.MPTemplatesFixtures do
  def mp_template_payload do
    %{
      "author" => "Synthetic Campaign Collective",
      "source" => "https://example.org/campaign-source",
      "editions" => %{
        "en" => %{
          "title" => "Synthetic briefing campaign",
          "purpose" => "Ask for a public briefing about a synthetic policy.",
          "subject" => "Request a public briefing",
          "body" => "Please arrange a public briefing about this synthetic campaign."
        },
        "fr" => %{
          "title" => "Campagne fictive de séance d’information",
          "purpose" => "Demander une séance publique sur une politique fictive.",
          "subject" => "Demande de séance d’information publique",
          "body" =>
            "Veuillez organiser une séance d’information publique sur cette campagne fictive."
        }
      }
    }
  end
end
