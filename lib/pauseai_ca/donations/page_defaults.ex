defmodule PauseAiCa.Donations.PageDefaults do
  @moduledoc "Public-copy fallback and the brochure's complete cumulative scenario budgets. No source files are read at runtime."
  # Public source: https://drive.google.com/file/d/1AzvdAml-q0DAWhhSu-Q7K5RiTvFObFXu/view
  # Targets describe complete alternative funding stages and must never be summed.
  def payload do
    %{
      "currency" => "CAD",
      "editions" => %{
        "en" => %{
          "title" => "Support PauseAI Canada",
          "lead" =>
            "Help Canadians make the case for an international pause on the development of the most powerful AI systems. Your donation helps people organize locally, explain the risks, and bring concrete requests to elected representatives.",
          "brochure_label" => "Read our brochure (PDF)",
          "campaign_heading" => "What your support makes possible",
          "campaign_body" =>
            "Support local groups in Toronto and across Canada, public meetings and outreach materials, and research and briefings for conversations with MPs.",
          "cta_label" => "Donate on Manifund",
          "account_requirement" =>
            "A Manifund account is required to donate. You can read the full proposal without an account.",
          "proposal_label" => "Read the full proposal",
          "unavailable_note" =>
            "The Manifund campaign link is unavailable here. You can still donate by Interac below.",
          "interac_heading" => "Or donate by Interac e-Transfer",
          "interac_body" =>
            "Send your donation from your banking app to the address below. Autodeposit is enabled. Check that the recipient name is PauseAI Canada before confirming.",
          "recipient_label" => "Recipient",
          "allocation_heading" => "How your donation could help",
          "allocation_note" => "Explore successive funding stages.",
          "remaining_heading" => "Remaining costs",
          "remaining_note" => "See the remaining costs in this funding stage.",
          "gift_label" => "Your donation (CAD)",
          "gift_note" =>
            "Every amount counts. If you can’t contribute right now, you can still follow our project on Manifund.",
          "funding_unknown" =>
            "Verified donation totals are unavailable. The illustration starts from zero.",
          "projection_note" =>
            "This illustration shows how a donation could cover planned costs. It does not record a payment or change the funding total.",
          "remaining_label" => "Still needed",
          "covered_label" => "Covered",
          "toward_label" => "Towards",
          "after_gift_label" => "With your donation",
          "complete_note" => "All costs in this stage are covered in this illustration.",
          "budget_label" => "Planning budget",
          "gift_invalid" => "Enter a non-negative CAD amount with at most two decimal places."
        },
        "fr" => %{
          "title" => "PauseIA Canada a besoin de vous !",
          "lead" =>
            "Aidez les Canadiennes et les Canadiens à défendre une pause internationale dans le développement des systèmes d’IA les plus puissants. Votre don aide à organiser des activités locales, à expliquer les risques et à présenter des demandes concrètes aux personnes élues.",
          "brochure_label" => "Lire notre brochure (PDF)",
          "campaign_heading" => "Ce que votre soutien rend possible",
          "campaign_body" =>
            "Soutenez les groupes locaux à Toronto et ailleurs au Canada, les rencontres publiques et les outils de sensibilisation, ainsi que la recherche et les documents préparatoires aux échanges avec les député·es.",
          "cta_label" => "Faire un don sur Manifund",
          "account_requirement" =>
            "Un compte Manifund est nécessaire pour faire un don. Vous pouvez consulter la proposition complète sans compte.",
          "proposal_label" => "Consulter la proposition complète",
          "unavailable_note" =>
            "Le lien vers la campagne Manifund est indisponible ici. Vous pouvez toujours faire un don par Interac ci-dessous.",
          "interac_heading" => "Ou faire un don par Virement Interac",
          "interac_body" =>
            "Envoyez votre don depuis votre application bancaire à l’adresse ci-dessous. Le dépôt automatique est activé. Vérifiez que le nom du destinataire est PauseAI Canada avant de confirmer.",
          "recipient_label" => "Destinataire",
          "allocation_heading" => "Comment votre don pourrait aider",
          "allocation_note" => "Explorez les étapes successives de financement.",
          "remaining_heading" => "Coûts restants",
          "remaining_note" => "Consultez les coûts restants de cette étape de financement.",
          "gift_label" => "Votre don (CAD)",
          "gift_note" =>
            "Chaque montant compte. Si vous ne pouvez pas contribuer pour le moment, vous pouvez aussi suivre notre projet sur Manifund avec le bouton « Follow ».",
          "funding_unknown" =>
            "Le total vérifié des dons est indisponible. Cette illustration commence à zéro.",
          "projection_note" =>
            "Cette illustration montre comment un don pourrait couvrir les coûts prévus. Elle n’enregistre aucun paiement et ne modifie pas le total du financement.",
          "remaining_label" => "Reste à financer",
          "covered_label" => "Couvert",
          "toward_label" => "Pour",
          "after_gift_label" => "Avec votre don",
          "complete_note" =>
            "Tous les coûts de cette étape sont couverts dans cette illustration.",
          "budget_label" => "Budget prévisionnel",
          "gift_invalid" =>
            "Saisissez un montant en dollars canadiens positif ou nul, avec au plus deux décimales."
        }
      },
      "links" => %{
        "brochure" => "https://drive.google.com/file/d/1AzvdAml-q0DAWhhSu-Q7K5RiTvFObFXu/view",
        "campaign" =>
          "https://manifund.org/projects/pauseai-canada-national-expansion--core-operations"
      },
      "display" => %{
        "mode" => "remaining_after_threshold",
        "remaining_threshold_percent" => 50,
        "show_remaining_above" => true
      },
      "stages" => [
        %{
          "id" => "toronto-launch",
          "label_en" => "Toronto launch · 3 months",
          "label_fr" => "Lancement à Toronto · 3 mois",
          "target_minor" => 1_400_000,
          "buckets" => [
            %{
              "id" => "meetups",
              "label_en" => "Monthly meetups: venue and food",
              "label_fr" => "Rencontres mensuelles : salle et nourriture",
              "amount_minor" => 300_000
            },
            %{
              "id" => "talks",
              "label_en" => "Public talks and screenings",
              "label_fr" => "Conférences publiques et projections",
              "amount_minor" => 200_000
            },
            %{
              "id" => "protest",
              "label_en" => "One protest: signs, sound and permits",
              "label_fr" => "Une manifestation : pancartes, sonorisation et permis",
              "amount_minor" => 150_000
            },
            %{
              "id" => "media",
              "label_en" => "Video and photo production",
              "label_fr" => "Production vidéo et photo",
              "amount_minor" => 200_000
            },
            %{
              "id" => "promotion",
              "label_en" => "Promoting posts and events",
              "label_fr" => "Promotion des publications et événements",
              "amount_minor" => 150_000
            },
            %{
              "id" => "printing",
              "label_en" => "Flyers, brochures, stickers and shirts",
              "label_fr" => "Dépliants, brochures, autocollants et chandails",
              "amount_minor" => 150_000
            },
            %{
              "id" => "campuses",
              "label_en" => "Talks and letter-writing with student clubs",
              "label_fr" => "Conférences et soirées de lettres avec les clubs étudiants",
              "amount_minor" => 150_000
            },
            %{
              "id" => "travel",
              "label_en" => "Travel between Toronto, Montréal and Ottawa",
              "label_fr" => "Déplacements entre Toronto, Montréal et Ottawa",
              "amount_minor" => 60000
            },
            %{
              "id" => "software",
              "label_en" => "Newsletter, design and event software",
              "label_fr" => "Logiciels d’infolettre, de conception et d’événements",
              "amount_minor" => 40000
            }
          ]
        },
        %{
          "id" => "two-city-pilot",
          "label_en" => "Two-city pilot · 3 months",
          "label_fr" => "Projet pilote dans deux villes · 3 mois",
          "target_minor" => 3_800_000,
          "buckets" => [
            %{
              "id" => "two-city-pilot-1",
              "label_en" => "National leader, half-time",
              "label_fr" => "Responsable national·e à mi-temps",
              "amount_minor" => 675_000
            },
            %{
              "id" => "two-city-pilot-2",
              "label_en" => "Toronto lead, half-time",
              "label_fr" => "Responsable de Toronto à mi-temps",
              "amount_minor" => 675_000
            },
            %{
              "id" => "two-city-pilot-3",
              "label_en" => "Payroll costs (CPP and EI)",
              "label_fr" => "Charges salariales (RPC et assurance-emploi)",
              "amount_minor" => 111_100
            },
            %{
              "id" => "two-city-pilot-4",
              "label_en" => "Bilingual content and event coverage",
              "label_fr" => "Contenu bilingue et couverture des événements",
              "amount_minor" => 300_000
            },
            %{
              "id" => "two-city-pilot-5",
              "label_en" => "Six local meetings: venue and food",
              "label_fr" => "Six rencontres locales : salle et nourriture",
              "amount_minor" => 600_000
            },
            %{
              "id" => "two-city-pilot-6",
              "label_en" => "One public action",
              "label_fr" => "Une action publique",
              "amount_minor" => 150_000
            },
            %{
              "id" => "two-city-pilot-7",
              "label_en" => "One campus collaboration",
              "label_fr" => "Une collaboration sur un campus",
              "amount_minor" => 150_000
            },
            %{
              "id" => "two-city-pilot-8",
              "label_en" => "Paid promotion",
              "label_fr" => "Promotion payante",
              "amount_minor" => 50000
            },
            %{
              "id" => "two-city-pilot-9",
              "label_en" => "Printing",
              "label_fr" => "Impression",
              "amount_minor" => 100_000
            },
            %{
              "id" => "two-city-pilot-10",
              "label_en" => "Travel",
              "label_fr" => "Déplacements",
              "amount_minor" => 100_000
            },
            %{
              "id" => "two-city-pilot-11",
              "label_en" => "Legal, accounting and insurance",
              "label_fr" => "Services juridiques, comptabilité et assurance",
              "amount_minor" => 200_000
            },
            %{
              "id" => "two-city-pilot-12",
              "label_en" => "Organizing software",
              "label_fr" => "Logiciels d’organisation",
              "amount_minor" => 30000
            },
            %{
              "id" => "two-city-pilot-13",
              "label_en" => "Organizing contingency",
              "label_fr" => "Imprévus liés à l’organisation",
              "amount_minor" => 158_900
            },
            %{
              "id" => "two-city-pilot-14",
              "label_en" => "Website infrastructure: hosting, maintenance and tools",
              "label_fr" => "Infrastructure du site : hébergement, maintenance et outils",
              "amount_minor" => 500_000
            }
          ]
        },
        %{
          "id" => "national-programme",
          "label_en" => "National programme · 1 year",
          "label_fr" => "Programme national · 1 an",
          "target_minor" => 31_500_000,
          "buckets" => [
            %{
              "id" => "national-programme-1",
              "label_en" => "Executive director",
              "label_fr" => "Direction générale",
              "amount_minor" => 6_600_000
            },
            %{
              "id" => "national-programme-2",
              "label_en" => "Communications lead, from February",
              "label_fr" => "Responsable des communications, dès février",
              "amount_minor" => 5_000_000
            },
            %{
              "id" => "national-programme-3",
              "label_en" => "Toronto lead, half-time",
              "label_fr" => "Responsable de Toronto à mi-temps",
              "amount_minor" => 2_700_000
            },
            %{
              "id" => "national-programme-4",
              "label_en" => "Montréal lead, half-time",
              "label_fr" => "Responsable de Montréal à mi-temps",
              "amount_minor" => 2_700_000
            },
            %{
              "id" => "national-programme-5",
              "label_en" => "Payroll costs (CPP and EI)",
              "label_fr" => "Charges salariales (RPC et assurance-emploi)",
              "amount_minor" => 1_399_100
            },
            %{
              "id" => "national-programme-6",
              "label_en" => "Video and content creator, contract",
              "label_fr" => "Création vidéo et de contenu, à contrat",
              "amount_minor" => 1_800_000
            },
            %{
              "id" => "national-programme-7",
              "label_en" => "Policy consultant in Ottawa, from March",
              "label_fr" => "Conseil en politiques publiques à Ottawa, dès mars",
              "amount_minor" => 1_800_000
            },
            %{
              "id" => "national-programme-8",
              "label_en" => "Fundraising consultant",
              "label_fr" => "Conseil en collecte de fonds",
              "amount_minor" => 800_000
            },
            %{
              "id" => "national-programme-9",
              "label_en" => "Meetups, talks and screenings in three cities",
              "label_fr" => "Rencontres, conférences et projections dans trois villes",
              "amount_minor" => 1_200_000
            },
            %{
              "id" => "national-programme-10",
              "label_en" => "Three protests, including a national day of action",
              "label_fr" => "Trois manifestations, dont une journée nationale d’action",
              "amount_minor" => 900_000
            },
            %{
              "id" => "national-programme-11",
              "label_en" => "Campus programme, about 15 clubs",
              "label_fr" => "Programme sur les campus, environ 15 clubs",
              "amount_minor" => 900_000
            },
            %{
              "id" => "national-programme-12",
              "label_en" => "Paid promotion",
              "label_fr" => "Promotion payante",
              "amount_minor" => 900_000
            },
            %{
              "id" => "national-programme-13",
              "label_en" => "Printing",
              "label_fr" => "Impression",
              "amount_minor" => 400_000
            },
            %{
              "id" => "national-programme-14",
              "label_en" => "Travel",
              "label_fr" => "Déplacements",
              "amount_minor" => 600_000
            },
            %{
              "id" => "national-programme-15",
              "label_en" => "Coworking space",
              "label_fr" => "Espace de travail partagé",
              "amount_minor" => 600_000
            },
            %{
              "id" => "national-programme-16",
              "label_en" => "Legal, accounting and insurance",
              "label_fr" => "Services juridiques, comptabilité et assurance",
              "amount_minor" => 400_000
            },
            %{
              "id" => "national-programme-17",
              "label_en" => "Software and AI tools",
              "label_fr" => "Logiciels et outils d’IA",
              "amount_minor" => 180_000
            },
            %{
              "id" => "national-programme-18",
              "label_en" => "Website infrastructure: hosting, maintenance and tools",
              "label_fr" => "Infrastructure du site : hébergement, maintenance et outils",
              "amount_minor" => 1_500_000
            },
            %{
              "id" => "national-programme-19",
              "label_en" => "Operational costs and buffer",
              "label_fr" => "Frais de fonctionnement et réserve",
              "amount_minor" => 1_120_900
            }
          ]
        },
        %{
          "id" => "two-year-expansion",
          "label_en" => "National expansion · 2 years",
          "label_fr" => "Expansion nationale · 2 ans",
          "target_minor" => 159_500_000,
          "buckets" => [
            %{
              "id" => "two-year-expansion-1",
              "label_en" => "Executive director, year one",
              "label_fr" => "Direction générale, première année",
              "amount_minor" => 7_200_000
            },
            %{
              "id" => "two-year-expansion-2",
              "label_en" => "Communications director, year one",
              "label_fr" => "Direction des communications, première année",
              "amount_minor" => 6_600_000
            },
            %{
              "id" => "two-year-expansion-3",
              "label_en" => "Community organizer, from January",
              "label_fr" => "Organisation communautaire, dès janvier",
              "amount_minor" => 5_500_000
            },
            %{
              "id" => "two-year-expansion-4",
              "label_en" => "Video content creator, from January",
              "label_fr" => "Création de contenu vidéo, dès janvier",
              "amount_minor" => 5_500_000
            },
            %{
              "id" => "two-year-expansion-5",
              "label_en" => "Policy lead in Ottawa, from February",
              "label_fr" => "Responsable des politiques à Ottawa, dès février",
              "amount_minor" => 6_000_000
            },
            %{
              "id" => "two-year-expansion-6",
              "label_en" => "Campus programme coordinator, from February",
              "label_fr" => "Coordination du programme sur les campus, dès février",
              "amount_minor" => 4_500_000
            },
            %{
              "id" => "two-year-expansion-7",
              "label_en" => "Four half-time city leads, from February",
              "label_fr" => "Quatre responsables de ville à mi-temps, dès février",
              "amount_minor" => 9_000_000
            },
            %{
              "id" => "two-year-expansion-8",
              "label_en" => "Payroll costs (CPP and EI)",
              "label_fr" => "Charges salariales (RPC et assurance-emploi)",
              "amount_minor" => 3_645_900
            },
            %{
              "id" => "two-year-expansion-9",
              "label_en" => "PR and advertising agency",
              "label_fr" => "Agence de relations publiques et de publicité",
              "amount_minor" => 4_000_000
            },
            %{
              "id" => "two-year-expansion-10",
              "label_en" => "Video post-production and design",
              "label_fr" => "Postproduction vidéo et conception graphique",
              "amount_minor" => 2_000_000
            },
            %{
              "id" => "two-year-expansion-11",
              "label_en" => "Fundraising consultant",
              "label_fr" => "Conseil en collecte de fonds",
              "amount_minor" => 2_000_000
            },
            %{
              "id" => "two-year-expansion-12",
              "label_en" => "National gathering and public conference",
              "label_fr" => "Rassemblement national et conférence publique",
              "amount_minor" => 4_000_000
            },
            %{
              "id" => "two-year-expansion-13",
              "label_en" => "Meetups, talks and screenings in four cities",
              "label_fr" => "Rencontres, conférences et projections dans quatre villes",
              "amount_minor" => 1_800_000
            },
            %{
              "id" => "two-year-expansion-14",
              "label_en" => "Protests, including national days of action",
              "label_fr" => "Manifestations, dont des journées nationales d’action",
              "amount_minor" => 1_500_000
            },
            %{
              "id" => "two-year-expansion-15",
              "label_en" => "Campus programme, about 30 clubs",
              "label_fr" => "Programme sur les campus, environ 30 clubs",
              "amount_minor" => 1_500_000
            },
            %{
              "id" => "two-year-expansion-16",
              "label_en" => "Advertising",
              "label_fr" => "Publicité",
              "amount_minor" => 2_000_000
            },
            %{
              "id" => "two-year-expansion-17",
              "label_en" => "Printing",
              "label_fr" => "Impression",
              "amount_minor" => 800_000
            },
            %{
              "id" => "two-year-expansion-18",
              "label_en" => "Travel for staff and speakers",
              "label_fr" => "Déplacements du personnel et des intervenant·es",
              "amount_minor" => 1_500_000
            },
            %{
              "id" => "two-year-expansion-19",
              "label_en" => "Coworking, legal, accounting and insurance",
              "label_fr" =>
                "Espace de travail partagé, services juridiques, comptabilité et assurance",
              "amount_minor" => 2_000_000
            },
            %{
              "id" => "two-year-expansion-20",
              "label_en" => "Software and AI tools",
              "label_fr" => "Logiciels et outils d’IA",
              "amount_minor" => 300_000
            },
            %{
              "id" => "two-year-expansion-21",
              "label_en" => "Website infrastructure, year one",
              "label_fr" => "Infrastructure du site, première année",
              "amount_minor" => 2_500_000
            },
            %{
              "id" => "two-year-expansion-22",
              "label_en" => "Operational costs and buffer, year one",
              "label_fr" => "Frais de fonctionnement et réserve, première année",
              "amount_minor" => 3_654_100
            },
            %{
              "id" => "two-year-expansion-23",
              "label_en" =>
                "Year two: full-year team and operations, including C$20,000 website infrastructure",
              "label_fr" =>
                "Deuxième année : équipe et fonctionnement sur une année complète, dont 20 000 $ pour l’infrastructure du site",
              "amount_minor" => 82_000_000
            }
          ]
        }
      ]
    }
  end
end
