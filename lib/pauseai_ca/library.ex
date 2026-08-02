defmodule PauseAiCa.Library do
  @moduledoc """
  The reviewed bilingual reading library.

  Two collections: `resources/0`, links to material published by PauseAI, Pause
  IA and others, ordered along the curiosity-to-action progression; and
  `voices/0`, Canadians whose public positions on advanced AI risk a visitor can
  check for themselves.

  English and French are peer editions here, not a primary and a translation.
  Where only one language exists upstream, we say so on the card rather than
  pretending a French reader has the same material.
  """

  alias PauseAiCa.Library.Resource
  alias PauseAiCa.Library.Voice

  @stages [:curiosity, :risk, :responses, :coordination, :agency, :participation]

  @doc "The visitor-journey stages, in order."
  @spec stages() :: [Resource.stage()]
  def stages, do: @stages

  @doc "Every reviewed resource, in journey order."
  @spec resources() :: [Resource.t()]
  def resources do
    Enum.flat_map(@stages, &resources(&1))
  end

  @doc "Reviewed resources for one stage."
  @spec resources(Resource.stage()) :: [Resource.t()]
  def resources(stage) do
    Enum.filter(all_resources(), &(&1.stage == stage))
  end

  @doc "Canadian voices, with attributed quotations."
  @spec voices() :: [Voice.t()]
  def voices, do: all_voices()

  @doc """
  The label for `stage` in `locale`.
  """
  @spec stage_label(Resource.stage(), String.t()) :: String.t()
  def stage_label(stage, "fr"), do: Map.fetch!(french_stage_labels(), stage)
  def stage_label(stage, _locale), do: Map.fetch!(english_stage_labels(), stage)

  defp english_stage_labels do
    %{
      curiosity: "Start here",
      risk: "Understand the risk",
      responses: "Possible responses",
      coordination: "Can countries coordinate?",
      agency: "Why your voice counts",
      participation: "Take part"
    }
  end

  defp french_stage_labels do
    %{
      curiosity: "Commencer ici",
      risk: "Comprendre le risque",
      responses: "Les réponses possibles",
      coordination: "Les pays peuvent-ils se coordonner?",
      agency: "Pourquoi votre voix compte",
      participation: "Participer"
    }
  end

  @reviewed ~D[2026-08-02]

  defp all_resources do
    [
      %Resource{
        id: "pauseai-learn",
        stage: :curiosity,
        format: :article,
        language: "en",
        url: "https://pauseai.info/learn",
        publisher: "PauseAI",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "Start here: what the argument actually is",
            summary:
              "PauseAI's own entry point. What is being built, why the people building it say it is dangerous, and what a pause would and would not cover."
          },
          "fr" => %{
            title: "Commencer ici: en quoi consiste l'argument",
            summary:
              "Le point d'entrée de PauseAI. Ce qui est en construction, pourquoi celles et ceux qui le construisent le disent dangereux, et ce qu'une pause couvrirait ou non."
          }
        }
      },
      %Resource{
        id: "pauseia-faq",
        stage: :curiosity,
        format: :faq,
        language: "fr",
        url: "https://pauseia.fr/faq",
        publisher: "Pause IA",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "Frequently asked questions (in French)",
            summary:
              "Pause IA's answers to the questions that come up first, written for a French-speaking public rather than translated from English."
          },
          "fr" => %{
            title: "Foire aux questions",
            summary:
              "Les réponses de Pause IA aux questions qui reviennent en premier, écrites pour un public francophone plutôt que traduites de l'anglais."
          }
        }
      },
      %Resource{
        id: "safety-report",
        stage: :risk,
        format: :report,
        language: "en",
        url: "https://internationalaisafetyreport.org/",
        publisher: "International AI Safety Report",
        author: "Chaired by Yoshua Bengio",
        canadian: true,
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "The International AI Safety Report",
            summary:
              "The closest thing to an IPCC report for AI, chaired by Montréal's Yoshua Bengio and backed by thirty countries. Read the summary if you read nothing else."
          },
          "fr" => %{
            title: "Le Rapport international sur la sécurité de l'IA",
            summary:
              "Ce qui se rapproche le plus d'un rapport du GIEC pour l'IA, présidé par le Montréalais Yoshua Bengio et soutenu par une trentaine de pays. À lire en priorité, ne serait-ce que le résumé."
          }
        }
      },
      %Resource{
        id: "pauseai-xrisk",
        stage: :risk,
        format: :article,
        language: "en",
        url: "https://pauseai.info/xrisk",
        publisher: "PauseAI",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "Why researchers talk about existential risk",
            summary:
              "Loss of control, misuse and concentration of power, set out with the uncertainty left in rather than argued away."
          },
          "fr" => %{
            title: "Pourquoi les chercheur·ses parlent de risque existentiel",
            summary:
              "Perte de contrôle, mésusage et concentration du pouvoir, exposés en conservant l'incertitude plutôt qu'en l'évacuant."
          }
        }
      },
      %Resource{
        id: "pauseia-humanite",
        stage: :risk,
        format: :article,
        language: "fr",
        url: "https://pauseia.fr/dangers/pour-l'humanite",
        publisher: "Pause IA",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "Dangers for humanity (in French)",
            summary:
              "Pause IA's account of the risks to humanity as a whole, and the clearest French-language starting point on loss of control."
          },
          "fr" => %{
            title: "Les dangers pour l'humanité",
            summary:
              "L'exposé de Pause IA sur les risques pour l'humanité entière, et le point de départ francophone le plus clair sur la perte de contrôle."
          }
        }
      },
      %Resource{
        id: "bengio-rogue-ai",
        stage: :risk,
        format: :article,
        language: "en",
        url: "https://yoshuabengio.org/2023/05/22/how-rogue-ais-may-arise/",
        publisher: "yoshuabengio.org",
        author: "Yoshua Bengio",
        canadian: true,
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "How rogue AIs may arise",
            summary:
              "The essay in which one of deep learning's founders set out, in his own words, why he changed his mind about the risk."
          },
          "fr" => %{
            title: "Comment des IA malveillantes peuvent apparaître",
            summary:
              "L'essai dans lequel l'un des fondateurs de l'apprentissage profond explique, dans ses propres mots, pourquoi il a changé d'avis sur le risque."
          }
        }
      },
      %Resource{
        id: "pauseai-proposal",
        stage: :responses,
        format: :article,
        language: "en",
        url: "https://pauseai.info/proposal",
        publisher: "PauseAI",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "What a pause would actually mean",
            summary:
              "What would stop, what would continue, and why this is not a ban on AI. The specific proposal, not the slogan."
          },
          "fr" => %{
            title: "Ce que signifierait réellement une pause",
            summary:
              "Ce qui s'arrêterait, ce qui continuerait, et pourquoi il ne s'agit pas d'une interdiction de l'IA. La proposition précise, pas le slogan."
          }
        }
      },
      %Resource{
        id: "pauseia-propositions",
        stage: :responses,
        format: :article,
        language: "fr",
        url: "https://pauseia.fr/propositions",
        publisher: "Pause IA",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "Pause IA's proposals (in French)",
            summary:
              "The French chapter's policy asks, useful for seeing how the same argument is made inside another legal system."
          },
          "fr" => %{
            title: "Les propositions de Pause IA",
            summary:
              "Les demandes politiques de la section française, utiles pour voir comment le même argument se formule dans un autre système juridique."
          }
        }
      },
      %Resource{
        id: "lawzero",
        stage: :responses,
        format: :organization,
        language: "en",
        url: "https://lawzero.org/",
        publisher: "LawZero",
        author: "Founded by Yoshua Bengio",
        canadian: true,
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "LawZero: building AI that does not act on its own",
            summary:
              "The Montréal non-profit Bengio founded to pursue non-agentic, verifiable AI — evidence that technical work and a pause are not opposed."
          },
          "fr" => %{
            title: "LawZero: construire une IA qui n'agit pas d'elle-même",
            summary:
              "L'organisme montréalais fondé par Bengio pour développer une IA non agentique et vérifiable — la preuve que travaux techniques et pause ne s'opposent pas."
          }
        }
      },
      %Resource{
        id: "pauseai-counterarguments",
        stage: :coordination,
        format: :article,
        language: "en",
        url: "https://pauseai.info/counterarguments",
        publisher: "PauseAI",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "The strongest objections, stated fairly",
            summary:
              "Including the one most people raise first: another country will keep going anyway. Read this before deciding you disagree."
          },
          "fr" => %{
            title: "Les objections les plus fortes, présentées honnêtement",
            summary:
              "Y compris celle que l'on soulève en premier: un autre pays continuera de toute façon. À lire avant de conclure que vous n'êtes pas d'accord."
          }
        }
      },
      %Resource{
        id: "pauseai-feasibility",
        stage: :coordination,
        format: :article,
        language: "en",
        url: "https://pauseai.info/feasibility",
        publisher: "PauseAI",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "Could an international agreement actually be enforced?",
            summary:
              "Advanced chips, compute centres, inspection and defection — the mechanics of verification rather than an appeal to good intentions."
          },
          "fr" => %{
            title: "Un accord international pourrait-il vraiment être appliqué?",
            summary:
              "Puces avancées, centres de calcul, inspection et défection: la mécanique de la vérification plutôt qu'un appel aux bonnes intentions."
          }
        }
      },
      %Resource{
        id: "aigs-canada",
        stage: :agency,
        format: :organization,
        language: "en",
        url: "https://aigs.ca/",
        publisher: "AI Governance & Safety Canada",
        canadian: true,
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "AI Governance & Safety Canada",
            summary:
              "The Canadian civil-society organization that testifies before parliamentary committees on advanced AI. Useful for seeing what is already on the record in Ottawa."
          },
          "fr" => %{
            title: "Gouvernance et sécurité de l'IA Canada",
            summary:
              "L'organisme canadien de la société civile qui témoigne devant les comités parlementaires sur l'IA avancée. Utile pour voir ce qui figure déjà au compte rendu à Ottawa."
          }
        }
      },
      %Resource{
        id: "pauseai-quotes",
        stage: :agency,
        format: :article,
        language: "en",
        url: "https://pauseai.info/quotes",
        publisher: "PauseAI",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "Who else is saying this",
            summary:
              "Researchers, executives and heads of state, quoted with sources. The point is that this is not a fringe position."
          },
          "fr" => %{
            title: "Qui d'autre le dit",
            summary:
              "Chercheur·ses, dirigeant·es d'entreprise et chef·fes d'État, cité·es avec leurs sources. L'enjeu: ce n'est pas une position marginale."
          }
        }
      },
      %Resource{
        id: "pauseai-action",
        stage: :participation,
        format: :article,
        language: "en",
        url: "https://pauseai.info/action",
        publisher: "PauseAI",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "Things you can do, ranked by effort",
            summary: "From a single email to organizing locally. No account needed to start."
          },
          "fr" => %{
            title: "Ce que vous pouvez faire, par ordre d'effort",
            summary:
              "D'un simple courriel à l'organisation locale. Aucun compte n'est nécessaire pour commencer."
          }
        }
      },
      %Resource{
        id: "pauseia-agir",
        stage: :participation,
        format: :article,
        language: "fr",
        url: "https://pauseia.fr/agir",
        publisher: "Pause IA",
        reviewed_on: @reviewed,
        copy: %{
          "en" => %{
            title: "Take action (in French)",
            summary:
              "Pause IA's action list, for French-speaking readers who prefer to organize in French."
          },
          "fr" => %{
            title: "Agir",
            summary:
              "La liste d'actions de Pause IA, pour les lecteur·rices francophones qui préfèrent s'organiser en français."
          }
        }
      }
    ]
  end

  defp all_voices do
    [
      %Voice{
        id: "bengio",
        name: "Yoshua Bengio",
        affiliation: %{
          "en" =>
            "Université de Montréal and Mila · Turing Award · chaired the International AI Safety Report",
          "fr" =>
            "Université de Montréal et Mila · prix Turing · a présidé le Rapport international sur la sécurité de l'IA"
        },
        url: "https://yoshuabengio.org/2023/05/22/how-rogue-ais-may-arise/",
        source: "yoshuabengio.org",
        reviewed_on: @reviewed,
        quote: %{
          "en" => "How rogue AIs may arise.",
          "fr" => "Comment des IA malveillantes peuvent apparaître."
        },
        note: %{
          "en" =>
            "One of the three researchers whose work made modern AI possible, who now argues publicly for slowing it down.",
          "fr" =>
            "L'un des trois chercheurs dont les travaux ont rendu l'IA moderne possible, et qui plaide aujourd'hui publiquement pour la ralentir."
        }
      },
      %Voice{
        id: "hinton",
        name: "Geoffrey Hinton",
        affiliation: %{
          "en" => "University of Toronto · Nobel Prize in Physics 2024 · Turing Award",
          "fr" => "Université de Toronto · prix Nobel de physique 2024 · prix Turing"
        },
        url: "https://pauseai.info/quotes",
        source: "PauseAI, quotes with sources",
        reviewed_on: @reviewed,
        quote: %{
          "en" =>
            "Left Google in 2023 to speak freely about the risks of the technology he helped create.",
          "fr" =>
            "A quitté Google en 2023 pour parler librement des risques de la technologie qu'il a contribué à créer."
        },
        note: nil
      },
      %Voice{
        id: "krueger",
        name: "David Krueger",
        affiliation: %{
          "en" => "Mila, Université de Montréal · AI safety researcher",
          "fr" => "Mila, Université de Montréal · chercheur en sécurité de l'IA"
        },
        url: "https://pauseai.info/xrisk",
        source: "PauseAI",
        reviewed_on: @reviewed,
        quote: %{
          "en" =>
            "Works on loss-of-control risk from inside the research community, not outside it.",
          "fr" =>
            "Travaille sur le risque de perte de contrôle depuis l'intérieur de la communauté de recherche, et non de l'extérieur."
        },
        note: nil
      },
      %Voice{
        id: "tessari",
        name: "Wyatt Tessari L'Allié",
        affiliation: %{
          "en" => "Founder and executive director, AI Governance & Safety Canada",
          "fr" => "Fondateur et directeur général, Gouvernance et sécurité de l'IA Canada"
        },
        url: "https://aigs.ca/",
        source: "AIGS Canada",
        reviewed_on: @reviewed,
        quote: %{
          "en" =>
            "Has testified to House of Commons committees that advanced AI is a national security matter.",
          "fr" =>
            "A témoigné devant des comités de la Chambre des communes que l'IA avancée relève de la sécurité nationale."
        },
        note: %{
          "en" =>
            "The most direct route from a Canadian concern to a Canadian parliamentary record.",
          "fr" =>
            "Le chemin le plus direct entre une préoccupation canadienne et le compte rendu parlementaire."
        }
      },
      %Voice{
        id: "hadfield",
        name: "Gillian Hadfield",
        affiliation: %{
          "en" =>
            "Johns Hopkins · on leave from the University of Toronto · CIFAR AI Chair, Vector Institute",
          "fr" =>
            "Johns Hopkins · en congé de l'Université de Toronto · chaire en IA CIFAR, Institut Vecteur"
        },
        url: "https://vectorinstitute.ai/team/gillian-k-hadfield/",
        source: "Vector Institute",
        reviewed_on: @reviewed,
        quote: %{
          "en" =>
            "Works on how you would actually regulate a technology that changes faster than law does.",
          "fr" =>
            "Travaille sur la manière de réglementer concrètement une technologie qui évolue plus vite que le droit."
        },
        note: nil
      }
    ]
  end
end
