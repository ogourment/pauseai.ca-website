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

  alias PauseAiCa.Library.Reference
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
            title: "What is actually being built",
            summary:
              "Systems that write code, use tools and pursue goals over hours without supervision — and why the labs building them say so themselves."
          },
          "fr" => %{
            title: "Ce qui est réellement en train d'être construit",
            summary:
              "Des systèmes qui écrivent du code, utilisent des outils et poursuivent des objectifs pendant des heures sans supervision — et pourquoi les laboratoires qui les construisent le disent eux-mêmes."
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
            title: "The questions people ask first",
            summary:
              "Is this science fiction? Is it not just hype? What about the benefits? Pause IA's answers, written in French for a French-speaking public."
          },
          "fr" => %{
            title: "Foire aux questions",
            summary:
              "Est-ce de la science-fiction? N'est-ce pas que du battage? Et les bénéfices? Les réponses de Pause IA, écrites en français pour un public francophone."
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
              "Thirty countries, one report, chaired from Montréal: what the evidence currently supports about AI capabilities and harms, and where experts genuinely disagree."
          },
          "fr" => %{
            title: "Le Rapport international sur la sécurité de l'IA",
            summary:
              "Une trentaine de pays, un rapport, présidé depuis Montréal: ce que les données appuient actuellement sur les capacités et les dangers de l'IA, et là où les experts divergent réellement."
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
              "The argument that a system optimizing hard enough for any goal ends up wanting resources, self-preservation and no off switch — and why nobody knows how to rule that out."
          },
          "fr" => %{
            title: "Pourquoi les chercheur·ses parlent de risque existentiel",
            summary:
              "L'argument selon lequel un système qui optimise assez fort n'importe quel objectif finit par vouloir des ressources, sa propre survie et aucun interrupteur — et pourquoi personne ne sait l'exclure."
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
            title: "What is at stake for everyone",
            summary:
              "Loss of control, concentration of power, and the erosion of the human ability to decide. The clearest French-language treatment of the case."
          },
          "fr" => %{
            title: "Les dangers pour l'humanité",
            summary:
              "Perte de contrôle, concentration du pouvoir et érosion de la capacité humaine à décider. L'exposé francophone le plus clair sur la question."
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
              "Bengio walks through how a system with goals of its own could actually arise from the training methods in use today. Technical, but written to be followed."
          },
          "fr" => %{
            title: "Comment des IA malveillantes peuvent apparaître",
            summary:
              "Bengio explique comment un système doté de ses propres objectifs pourrait réellement émerger des méthodes d'entraînement actuelles. Technique, mais écrit pour être suivi."
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
            title: "What a pause would and would not stop",
            summary:
              "Not a ban on AI. A ceiling on training runs above a compute threshold, until safety methods catch up. Medical AI, translation and everything else continues."
          },
          "fr" => %{
            title: "Ce qu'une pause arrêterait, et ce qu'elle n'arrêterait pas",
            summary:
              "Pas une interdiction de l'IA. Un plafond sur les entraînements dépassant un seuil de calcul, jusqu'à ce que la sécurité rattrape. L'IA médicale, la traduction et le reste continuent."
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
            title: "The same case, in French law and politics",
            summary:
              "How Pause IA translates the argument into concrete demands on a European government — a useful comparison for what Canada could ask for."
          },
          "fr" => %{
            title: "Les propositions de Pause IA",
            summary:
              "Comment Pause IA traduit l'argument en demandes concrètes à un gouvernement européen — une comparaison utile pour ce que le Canada pourrait exiger."
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
              "Bengio's answer to \"so what should we build instead\": AI that reasons and explains but does not act, designed so its safety can be checked."
          },
          "fr" => %{
            title: "LawZero: construire une IA qui n'agit pas d'elle-même",
            summary:
              "La réponse de Bengio à « alors, que construire à la place »: une IA qui raisonne et explique mais n'agit pas, conçue pour que sa sûreté soit vérifiable."
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
            title: "Why a pause might not work",
            summary:
              "China will not stop. The technology is already out. Regulation only punishes the careful. PauseAI's answers to the objections it hears most, including the ones it concedes."
          },
          "fr" => %{
            title: "Pourquoi une pause pourrait ne pas fonctionner",
            summary:
              "La Chine ne s'arrêtera pas. La technologie est déjà sortie. La réglementation ne punit que les prudents. Les réponses de PauseAI aux objections les plus fréquentes, y compris celles qu'elle concède."
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
            title: "Could a treaty be enforced?",
            summary:
              "Frontier training needs enormous, physically traceable compute in a handful of data centres, built on chips from very few suppliers. That is what makes verification thinkable."
          },
          "fr" => %{
            title: "Un accord international pourrait-il vraiment être appliqué?",
            summary:
              "Les entraînements de pointe exigent une puissance de calcul énorme et physiquement traçable, concentrée dans quelques centres et bâtie sur des puces issues de très peu de fournisseurs. C'est ce qui rend la vérification pensable."
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
              "The organization that has been making this case to Canadian parliamentary committees since 2022, with the submissions and testimony to show for it."
          },
          "fr" => %{
            title: "Gouvernance et sécurité de l'IA Canada",
            summary:
              "L'organisme qui porte cet argument devant les comités parlementaires canadiens depuis 2022, mémoires et témoignages à l'appui."
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
            title: "Who else says this, in their own words",
            summary:
              "The CEOs of OpenAI, Anthropic and Google DeepMind have all signed a statement putting AI extinction risk alongside pandemics and nuclear war. Here they are, quoted with sources."
          },
          "fr" => %{
            title: "Qui d'autre le dit, dans ses propres mots",
            summary:
              "Les PDG d'OpenAI, d'Anthropic et de Google DeepMind ont tous signé une déclaration plaçant le risque d'extinction lié à l'IA aux côtés des pandémies et de la guerre nucléaire. Les voici, cité·es avec leurs sources."
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
            title: "What actually moves a government",
            summary:
              "Elected officials count letters. Most files get almost none. PauseAI's list of actions, from a five-minute email to organizing a local group."
          },
          "fr" => %{
            title: "Ce qui fait vraiment bouger un gouvernement",
            summary:
              "Les élu·es comptent les lettres. La plupart des dossiers n'en reçoivent presque aucune. La liste d'actions de PauseAI, du courriel de cinq minutes au groupe local."
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
            title: "Getting organized, in French",
            summary:
              "Pause IA's action list, for readers who would rather write, meet and organize in French."
          },
          "fr" => %{
            title: "Agir",
            summary:
              "La liste d'actions de Pause IA, pour celles et ceux qui préfèrent écrire, se rencontrer et s'organiser en français."
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
            "Université de Montréal and Mila. Turing Award. Chaired the International AI Safety Report.",
          "fr" =>
            "Université de Montréal et Mila. Prix Turing. A présidé le Rapport international sur la sécurité de l'IA."
        },
        quotes: [
          %{
            text: %{
              "en" =>
                "Rogue AI may be dangerous for the whole of humanity. Banning powerful AI systems (say beyond the abilities of GPT-4) that are given autonomy and agency would be a good start."
            },
            source: "PauseAI, quotes with sources",
            url: "https://pauseai.info/quotes",
            said_on: nil,
            language: "en"
          },
          %{
            text: %{
              "en" =>
                "It's very hard, in terms of your ego and feeling good about what you do, to accept the idea that the thing you've been working on for decades might actually be very dangerous to humanity."
            },
            source: "PauseAI, quotes with sources",
            url: "https://pauseai.info/quotes",
            said_on: nil,
            language: "en"
          }
        ],
        references: [
          %Reference{
            label: %{
              "en" => "How rogue AIs may arise — his own account of changing his mind",
              "fr" => "Comment des IA malveillantes peuvent apparaître — son propre récit"
            },
            url: "https://yoshuabengio.org/2023/05/22/how-rogue-ais-may-arise/",
            publisher: "yoshuabengio.org",
            language: "en"
          },
          %Reference{
            label: %{
              "en" => "The International AI Safety Report, which he chairs",
              "fr" => "Le Rapport international sur la sécurité de l'IA, qu'il préside"
            },
            url: "https://internationalaisafetyreport.org/",
            publisher: "International AI Safety Report",
            language: "en"
          },
          %Reference{
            label: %{
              "en" => "LawZero, the Montréal non-profit he founded",
              "fr" => "LawZero, l'organisme montréalais qu'il a fondé"
            },
            url: "https://lawzero.org/en",
            publisher: "LawZero",
            language: "en"
          }
        ]
      },
      %Voice{
        id: "hinton",
        name: "Geoffrey Hinton",
        affiliation: %{
          "en" => "University of Toronto. Nobel Prize in Physics 2024. Turing Award.",
          "fr" => "Université de Toronto. Prix Nobel de physique 2024. Prix Turing."
        },
        quotes: [
          %{
            text: %{
              "en" =>
                "If you take the existential risk seriously, as I now do, it might be quite sensible to just stop developing these things any further."
            },
            source: "PauseAI, quotes with sources",
            url: "https://pauseai.info/quotes",
            said_on: nil,
            language: "en"
          },
          %{
            text: %{
              "en" =>
                "The research question is: how do you prevent them from ever wanting to take control? And nobody knows the answer."
            },
            source: "PauseAI, quotes with sources",
            url: "https://pauseai.info/quotes",
            said_on: nil,
            language: "en"
          }
        ],
        references: [
          %Reference{
            label: %{
              "en" => "The one-sentence statement on extinction risk he signed",
              "fr" => "La déclaration d'une phrase sur le risque d'extinction qu'il a signée"
            },
            url: "https://www.safe.ai/work/statement-on-ai-risk",
            publisher: "Center for AI Safety",
            language: "en"
          },
          %Reference{
            label: %{
              "en" => "More quotations, each with its original source",
              "fr" => "D'autres citations, chacune avec sa source d'origine"
            },
            url: "https://pauseai.info/quotes",
            publisher: "PauseAI",
            language: "en"
          }
        ]
      },
      %Voice{
        id: "krueger",
        name: "David Krueger",
        affiliation: %{
          "en" => "Mila and Université de Montréal. Founding CEO of Evitable.",
          "fr" => "Mila et Université de Montréal. PDG fondateur d'Evitable."
        },
        quotes: [
          %{
            text: %{"en" => "AI is not inevitable."},
            source: "The Real AI",
            url: "https://therealartificialintelligence.substack.com/p/ai-is-not-inevitable",
            said_on: nil,
            language: "en"
          }
        ],
        references: [
          %Reference{
            label: %{
              "en" => "His blog, The Real AI",
              "fr" => "Son blogue, The Real AI"
            },
            url: "https://therealartificialintelligence.substack.com/p/ai-is-not-inevitable",
            publisher: "Substack",
            language: "en"
          },
          %Reference{
            label: %{
              "en" => "Evitable, the non-profit he founded",
              "fr" => "Evitable, l'organisme qu'il a fondé"
            },
            url: "https://www.evitable.org/",
            publisher: "Evitable",
            language: "en"
          },
          %Reference{
            label: %{
              "en" => "The statement on extinction risk he signed",
              "fr" => "La déclaration sur le risque d'extinction qu'il a signée"
            },
            url: "https://www.safe.ai/work/statement-on-ai-risk",
            publisher: "Center for AI Safety",
            language: "en"
          }
        ]
      },
      %Voice{
        id: "tessari",
        name: "Wyatt Tessari L'Allié",
        affiliation: %{
          "en" => "Founder and executive director, AI Governance & Safety Canada.",
          "fr" => "Fondateur et directeur général, Gouvernance et sécurité de l'IA Canada."
        },
        quotes: [
          %{
            text: %{
              "en" =>
                "Certain AI capabilities pose an unacceptable risk because they could lead to dangerous weaponization or loss of control scenarios: systems that, without the instruction or authorization of their users, can detect and evade monitoring, rewrite their own code, make copies of themselves, spawn other AI systems, commandeer resources or refuse shutdown."
            },
            source: "Standing Committee on Industry and Technology",
            url:
              "https://openparliament.ca/committees/industry-and-technology/45-1/27/wyatt-tessari-lallie-1/only/",
            said_on: "2026-03-09",
            language: "en"
          },
          %{
            text: %{
              "en" =>
                "What can we do in and from Canada to ensure that AI is safe and benefits everyone?"
            },
            source: "Standing Committee on Industry and Technology",
            url:
              "https://openparliament.ca/committees/industry-and-technology/45-1/27/wyatt-tessari-lallie-1/only/",
            said_on: "2026-03-09",
            language: "en"
          }
        ],
        references: [
          %Reference{
            label: %{
              "en" => "His March 2026 testimony in full, from Hansard",
              "fr" => "Son témoignage de mars 2026 en entier, tiré du hansard"
            },
            url:
              "https://openparliament.ca/committees/industry-and-technology/45-1/27/wyatt-tessari-lallie-1/only/",
            publisher: "openparliament.ca",
            language: "en"
          },
          %Reference{
            label: %{
              "en" => "AI Governance & Safety Canada, the organization he runs",
              "fr" => "Gouvernance et sécurité de l'IA Canada, l'organisme qu'il dirige"
            },
            url: "https://aigs.ca/",
            publisher: "AIGS Canada",
            language: "en"
          }
        ]
      },
      %Voice{
        id: "hadfield",
        name: "Gillian Hadfield",
        affiliation: %{
          "en" =>
            "Johns Hopkins, on leave from the University of Toronto. Canada CIFAR AI Chair at the Vector Institute.",
          "fr" =>
            "Johns Hopkins, en congé de l'Université de Toronto. Chaire en IA Canada-CIFAR à l'Institut Vecteur."
        },
        quotes: [
          %{
            text: %{
              "en" =>
                "Governments require the targets of regulation to purchase regulatory services from a government-licensed private regulator."
            },
            source: "Regulatory Markets: The Future of AI Governance",
            url: "https://arxiv.org/abs/2304.04914",
            said_on: "2023",
            language: "en"
          }
        ],
        references: [
          %Reference{
            label: %{
              "en" => "Regulatory Markets: The Future of AI Governance",
              "fr" => "Regulatory Markets: The Future of AI Governance"
            },
            url: "https://arxiv.org/abs/2304.04914",
            publisher: "arXiv",
            language: "en"
          },
          %Reference{
            label: %{
              "en" => "An interview on building rules AI can actually follow",
              "fr" => "Une entrevue sur la conception de règles que l'IA peut suivre"
            },
            url:
              "https://aihub.org/2025/05/22/interview-with-gillian-hadfield-normative-infrastructure-for-ai-alignment/",
            publisher: "AIhub",
            language: "en"
          },
          %Reference{
            label: %{
              "en" => "Her profile at the Vector Institute",
              "fr" => "Sa fiche à l'Institut Vecteur"
            },
            url: "https://vectorinstitute.ai/team/gillian-k-hadfield/",
            publisher: "Vector Institute",
            language: "en"
          }
        ]
      }
    ]
  end
end
