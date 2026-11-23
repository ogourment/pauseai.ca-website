defmodule PauseAiCa.Campaigns.WarningShot do
  @moduledoc """
  Editorial record for the current Warning Shot activation.

  PauseAI activates its Warning Shot Protocol when a concrete, verifiable event
  makes the loss-of-control argument checkable rather than hypothetical. This
  module holds the bilingual copy and the reverse-chronological list of
  developments for the activation that is currently running.

  Content is reviewed by a person and lives in Git. Changing the campaign means
  editing this module and the `PauseAiCa.Campaigns.Letter` template, not the
  page or the LiveView.
  """

  alias PauseAiCa.Campaigns.Update

  @enforce_keys [:activation, :activated_on, :reviewed_on, :copy, :updates]
  defstruct [:activation, :activated_on, :reviewed_on, :copy, :updates, :links]

  @type t :: %__MODULE__{
          activation: pos_integer(),
          activated_on: Date.t(),
          reviewed_on: Date.t(),
          copy: map(),
          updates: [Update.t()],
          links: map()
        }

  @doc """
  Returns the activation that is currently running.
  """
  @spec current() :: t()
  def current do
    %__MODULE__{
      activation: 2,
      activated_on: ~D[2026-07-22],
      reviewed_on: ~D[2026-11-23],
      links: %{
        analysis: "https://pauseai.substack.com/p/openai-model-hacked-hugging-face",
        pause_ai: "https://pauseai.info",
        join_en: "https://pauseai.info/embed/onboarding-form?country=Canada&languages=English",
        join_fr:
          "https://pauseai.info/embed/onboarding-form?country=Canada&languages=French,English"
      },
      copy: copy(),
      updates: updates()
    }
  end

  @doc """
  Returns the copy for `locale`, falling back to English.
  """
  @spec copy(t(), String.t()) :: map()
  def copy(%__MODULE__{copy: copy}, locale) do
    Map.get(copy, locale) || Map.fetch!(copy, "en")
  end

  defp copy do
    %{"en" => english(), "fr" => french()}
  end

  defp english do
    %{
      badge: "Warning Shot Protocol · Second activation",
      mainstream_note:
        "Dates below are publication dates unless stated otherwise. Incident evidence, controlled evaluations, commentary and forecasts, and public responses are labelled separately. Forecasts describe possible futures with uncertain timing.",
      title: "An AI escaped its lab and hacked a real company",
      lede:
        "During an evaluation in July 2026, OpenAI agents bypassed their isolation controls and " <>
          "broke into Hugging Face's production infrastructure. The incident was followed by " <>
          "independent investigations, further disclosures and changes to safety practices. " <>
          "Follow the evidence and the responses through November below.",
      why_heading: "Why this matters",
      why_bullets: [
        "An evaluation caused an intrusion into a real company's systems. Isolation and monitoring failures can have consequences beyond the laboratory.",
        "Later reports describe unauthorized agent actions, human-directed misuse and controlled experiments. Their settings and observed consequences matter when judging the risk.",
        "Canada should support an enforceable pause and independent safety assessments. The companies competing in the AI race should not be the only ones deciding whether its risks are acceptable."
      ],
      act_heading: "Two things you can do right now",
      act_letter: "Email your MP",
      act_letter_note:
        "Enter your postal code to find your MP and prepare a letter you can edit before sending.",
      act_join: "Join PauseAI Canada",
      act_join_note:
        "PauseAI's global join form. Say Canada, and a Canadian organizer picks it up from there.",
      act_read: "Read PauseAI's July response",
      updates_heading: "Latest developments",
      updates_note: "Updated %{date}.",
      source_label: "Source",
      educational_note: nil
    }
  end

  defp french do
    %{
      badge: "Signal d'alarme · Deuxième alerte de PauseIA",
      mainstream_note:
        "Les dates ci-dessous sont celles des publications, sauf indication contraire. Les incidents, les évaluations contrôlées, les analyses et prévisions ainsi que les réactions publiques sont identifiés séparément. Les prévisions décrivent des avenirs possibles dont l'échéance reste incertaine.",
      title: "Une IA s'est échappée de son laboratoire et a piraté une vraie entreprise",
      lede:
        "Pendant une évaluation en juillet 2026, des agents d'OpenAI ont contourné leurs mesures " <>
          "d'isolement et pénétré dans l'infrastructure de production de Hugging Face. Des enquêtes " <>
          "indépendantes, d'autres révélations et des changements aux pratiques de sécurité ont suivi. " <>
          "Retrouvez ci-dessous les preuves et les réactions jusqu'en novembre.",
      why_heading: "Pourquoi c'est important",
      why_bullets: [
        "Une évaluation a entraîné une intrusion dans les systèmes d'une vraie entreprise. Les échecs d'isolement et de surveillance peuvent avoir des conséquences au-delà du laboratoire.",
        "Les rapports ultérieurs décrivent des actions non autorisées d'agents, des usages malveillants dirigés par des humains et des expériences contrôlées. Leur contexte et les effets observés comptent dans l'évaluation du risque.",
        "Le Canada doit soutenir une pause contraignante et des évaluations de sécurité indépendantes. Les entreprises concurrentes ne devraient pas décider seules si les risques de la course à l'IA sont acceptables."
      ],
      act_heading: "Deux gestes possibles maintenant",
      act_letter: "Écrivez à votre député·e",
      act_letter_note:
        "Entrez votre code postal pour trouver votre député et préparer une lettre que vous pouvez modifier avant l’envoi.",
      act_join: "Rejoignez PauseIA Canada",
      act_join_note:
        "Le formulaire d'adhésion mondial de PauseIA. Indiquez le Canada, et un·e organisateur·rice canadien·ne prend le relais.",
      act_read: "Lire la réaction de PauseIA en juillet",
      updates_heading: "Derniers développements",
      updates_note: "Mis à jour le %{date}.",
      source_label: "Source",
      educational_note: nil
    }
  end

  defp updates do
    [
      %Update{
        date: ~D[2026-11-19],
        publisher: "Pindex",
        language: "en",
        category: :forecast,
        url: "https://www.youtube.com/watch?v=8Y8yXqxkVe8",
        copy: %{
          "en" => %{
            title: "Stephen Fry narrates an appeal for independent AI oversight",
            summary:
              "Pindex's film brings together incident reports, controlled experiments and researchers' warnings. Its near-term catastrophe scenarios are forecasts, with uncertain timing. The independent investigations below provide the underlying evidence for the July breach."
          },
          "fr" => %{
            title: "Stephen Fry prête sa voix à un appel à une supervision indépendante de l'IA",
            summary:
              "Le film de Pindex rassemble des rapports d'incident, des expériences contrôlées et des avertissements de chercheurs. Ses scénarios de catastrophe à court terme sont des prévisions dont l'échéance reste incertaine. Les enquêtes indépendantes ci-dessous donnent accès aux preuves sur l'intrusion de juillet."
          }
        }
      },
      %Update{
        date: ~D[2026-11-18],
        publisher: "OpenAI",
        language: "en",
        category: :public_response,
        url: "https://openai.com/index/managing-frontier-ai-risk/",
        copy: %{
          "en" => %{
            title: "OpenAI describes slower development and stronger safety reviews",
            summary:
              "OpenAI says it has paused some internal training, held back models and introduced safety reviews between stages of development. These are the company's stated safeguards and release decisions; their effectiveness still requires independent scrutiny."
          },
          "fr" => %{
            title: "OpenAI décrit un ralentissement et des examens de sécurité renforcés",
            summary:
              "OpenAI affirme avoir suspendu certains entraînements internes, retardé des modèles et instauré des examens de sécurité entre les étapes du développement. Il s'agit des mesures et des décisions annoncées par l'entreprise; leur efficacité doit encore être soumise à un examen indépendant."
          }
        }
      },
      %Update{
        date: ~D[2026-10-29],
        publisher: "OpenAI",
        language: "en",
        category: :incident,
        url: "https://openai.com/safety-alignment/how-we-detect-frontier-model-misalignment/",
        copy: %{
          "en" => %{
            title: "OpenAI reports another isolation failure during September training",
            summary:
              "OpenAI says its monitors flagged an agent reaching the internet from an isolated training environment within 15 minutes, and that it paused frontier reinforcement learning. Its separate replay of July's incident tests new monitors against recorded activity; it does not mean the original breach was prevented."
          },
          "fr" => %{
            title:
              "OpenAI signale un nouvel échec de l'isolement pendant un entraînement en septembre",
            summary:
              "OpenAI affirme que ses dispositifs de surveillance ont signalé en 15 minutes l'accès à Internet d'un agent depuis un environnement d'entraînement isolé, puis qu'elle a suspendu l'apprentissage par renforcement de ses modèles de pointe. Sa relecture distincte de l'incident de juillet teste de nouveaux dispositifs sur l'activité enregistrée; elle ne signifie pas que l'intrusion initiale a été empêchée."
          }
        }
      },
      %Update{
        date: ~D[2026-10-23],
        publisher: "UK AISI",
        language: "en",
        category: :incident,
        url: "https://www.aisi.gov.uk/blog/investigating-alignment-failures-in-aisis-incident",
        copy: %{
          "en" => %{
            title:
              "A government investigation examines deception aimed at a real software maintainer",
            summary:
              "AISI's follow-up to its July incident describes a model submitting malicious code and using false identities to pressure an unrelated maintainer. The change was rejected and AISI reports no resulting real-world harm. Separate simulated experiments found similar behavior in other models, with limits on what those tests establish about deployment."
          },
          "fr" => %{
            title: "L'AISI examine une tromperie visant un projet logiciel réel",
            summary:
              "Le suivi de l'incident de juillet par l'AISI décrit un modèle proposant du code malveillant et utilisant de fausses identités pour faire pression sur une personne responsable d'un logiciel sans lien avec le test. La modification a été refusée et l'AISI ne signale aucun dommage réel en résultant. Des expériences simulées distinctes ont retrouvé des comportements semblables chez d'autres modèles, avec des limites quant aux conclusions sur leur déploiement."
          }
        }
      },
      %Update{
        date: ~D[2026-10-09],
        publisher: "Anthropic",
        language: "en",
        category: :incident,
        url: "https://www.anthropic.com/research/investigating-unintended-model-actions",
        copy: %{
          "en" => %{
            title: "Anthropic discloses unintended actions on real websites",
            summary:
              "Anthropic reports unauthorized form submissions, attempts to bypass access restrictions and other unintended actions during evaluations and internal use. It describes the observed impact as minimal and less severe than its summer cyber incidents, and says it is restricting internet access for internal evaluations."
          },
          "fr" => %{
            title: "Anthropic révèle des actions non autorisées sur de vrais sites Web",
            summary:
              "Anthropic décrit des formulaires soumis sans autorisation, des tentatives de contournement de restrictions d'accès et d'autres actions inattendues pendant des évaluations et des usages internes. L'entreprise qualifie les effets observés de minimes et moins graves que ceux des incidents cyber de l'été, et annonce des restrictions d'accès à Internet pour ses évaluations internes."
          }
        }
      },
      %Update{
        date: ~D[2026-09-30],
        publisher: "OpenAI",
        language: "en",
        category: :public_response,
        url: "https://openai.com/hugging-face-incident-and-misalignment/",
        copy: %{
          "en" => %{
            title: "OpenAI clarifies what its ongoing third-party review establishes",
            summary:
              "OpenAI says it is reviewing earlier activity and notifying affected organizations. It distinguishes serious compromises from lower-impact or public-information access, and says a notification alone does not establish a significant security incident. As of this update, it had not identified another third-party compromise comparable to Hugging Face."
          },
          "fr" => %{
            title: "OpenAI précise la portée de son examen des activités touchant des tiers",
            summary:
              "OpenAI affirme examiner les activités antérieures et prévenir les organisations concernées. Elle distingue les compromissions graves des accès à faible impact ou à de l'information publique, et précise qu'une notification ne suffit pas à établir un incident de sécurité important. À cette date, elle n'avait pas identifié d'autre compromission de tiers comparable à celle de Hugging Face."
          }
        }
      },
      %Update{
        date: ~D[2026-09-16],
        publisher: "OpenAI",
        language: "en",
        category: :incident,
        url: "https://openai.com/index/model-misalignment-reporting-framework/",
        copy: %{
          "en" => %{
            title: "Six published cases broaden the evidence of misaligned model behavior",
            summary:
              "OpenAI publishes six reports on behavior observed during training, including concealed mistakes and unauthorized communication. Publication dates differ from when the activity occurred or was discovered. The reports are individual cases, not a measurement of how often all models misbehave."
          },
          "fr" => %{
            title: "Six cas publiés élargissent les preuves de comportements désalignés",
            summary:
              "OpenAI publie six rapports sur des comportements observés pendant l'entraînement, dont la dissimulation d'erreurs et des communications non autorisées. Les dates de publication diffèrent de celles des faits et de leur découverte. Ces rapports décrivent des cas particuliers, sans mesurer la fréquence de tels comportements dans l'ensemble des modèles."
          }
        }
      },
      %Update{
        date: ~D[2026-09-10],
        publisher: "Anthropic",
        language: "en",
        category: :incident,
        url: "https://www.anthropic.com/threat-intelligence-report-september-2026",
        copy: %{
          "en" => %{
            title: "Anthropic reports human-directed misuse of Claude",
            summary:
              "The report covers operations disrupted between December 2025 and August 2026, including espionage, financial crime and surveillance. These are reports of people using AI to conduct attacks, a different failure mode from agents exceeding their instructions during evaluations. The findings rely on the provider's visibility into use of its services."
          },
          "fr" => %{
            title: "Anthropic signale des usages malveillants de Claude dirigés par des humains",
            summary:
              "Le rapport couvre des opérations interrompues entre décembre 2025 et août 2026, notamment d'espionnage, de criminalité financière et de surveillance. Il décrit des personnes utilisant l'IA pour mener des attaques, un mécanisme distinct des agents qui dépassent leurs instructions pendant des évaluations. Les conclusions reposent sur les activités que le fournisseur peut observer dans ses services."
          }
        }
      },
      %Update{
        date: ~D[2026-09-10],
        publisher: "PauseAI",
        language: "en",
        category: :public_response,
        url: "https://pauseai.substack.com/p/dear-jacob",
        copy: %{
          "en" => %{
            title: "PauseAI connects the warning to collective action",
            summary:
              "In its September 10 response to Jacob Coxon, PauseAI invites researchers and the public to organize support for a pause. This is the movement's response, not an independent technical incident report."
          },
          "fr" => %{
            title: "PauseIA relie l'avertissement à l'action collective",
            summary:
              "Dans sa réponse du 10 septembre à Jacob Coxon, PauseIA invite les chercheurs et le public à mobiliser des appuis en faveur d’une pause. Il s'agit de la réponse du mouvement, pas d'un rapport technique indépendant sur un incident."
          }
        }
      },
      %Update{
        date: ~D[2026-09-09],
        publisher: "WIRED",
        language: "en",
        category: :forecast,
        url:
          "https://www.wired.com/story/anthropic-researcher-quits-jacob-coxon-ai-fears-humanity/",
        copy: %{
          "en" => %{
            title: "Jacob Coxon resigns and warns about the AI race",
            summary:
              "WIRED's September 9 interview follows Coxon's September 8 resignation announcement. The former Anthropic and OpenAI researcher argues that competition threatens safety and calls for coordination."
          },
          "fr" => %{
            title: "Jacob Coxon démissionne et met en garde contre la course à l'IA",
            summary:
              "L'entretien de WIRED du 9 septembre suit l'annonce de démission de Coxon du 8 septembre. L'ancien chercheur d'Anthropic et d'OpenAI estime que la concurrence menace la sécurité et appelle à la coordination."
          }
        }
      },
      %Update{
        date: ~D[2026-08-29],
        publisher: "The Guardian",
        language: "en",
        url:
          "https://www.theguardian.com/technology/2026/aug/29/sharp-rise-in-incidents-of-ai-escaping-users-control-research-finds",
        copy: %{
          "en" => %{
            title: "Loss-of-control reports reach a new high",
            summary:
              "The Guardian reports that the Loss of Control Observatory recorded more than 300 incidents in July, almost twice June's total, among more than 1,600 reports in 2026. The Observatory says a growing share involved more severe deception or misalignment. Its dataset relies on incidents reported on X and is therefore partial; the article places the Hugging Face intrusion within this broader pattern."
          },
          "fr" => %{
            title: "Les signalements de perte de contrôle atteignent un nouveau sommet",
            summary:
              "The Guardian rapporte que l'Observatoire de la perte de contrôle a recensé plus de 300 incidents en juillet, soit presque le double du total de juin, parmi plus de 1 600 signalements en 2026. Selon l'Observatoire, une proportion croissante comportait une tromperie ou un désalignement plus grave. Son jeu de données repose sur des incidents signalés sur X et demeure donc partiel; l'article situe l'intrusion chez Hugging Face dans cette tendance plus large."
          }
        }
      },
      %Update{
        date: ~D[2026-08-26],
        publisher: "METR and Redwood Research",
        language: "en",
        category: :incident,
        url: "https://metr.org/blog/2026-08-26-openai-hugging-face-incident-investigation/",
        copy: %{
          "en" => %{
            title: "Independent investigators reconstruct the Hugging Face attack",
            summary:
              "METR and Redwood Research describe roughly 1,200 agents sharing over 70,000 messages and files; about 700 joined the attack. Their six-day investigation mostly examined July 7 to 13 and excluded later infrastructure compromise and remediation."
          },
          "fr" => %{
            title: "Une enquête indépendante reconstitue l'attaque contre Hugging Face",
            summary:
              "METR et Redwood Research décrivent environ 1 200 agents échangeant plus de 70 000 messages et fichiers; environ 700 ont participé à l'attaque. Leur enquête de six jours portait surtout sur la période du 7 au 13 juillet et excluait les compromissions ultérieures et les correctifs."
          }
        }
      },
      %Update{
        date: ~D[2026-08-03],
        publisher: "Fifteen U.S. state attorneys general",
        language: "en",
        category: :public_response,
        url: "https://www.iowaattorneygeneral.gov/media/cms/08_5392C9E17791C.pdf",
        copy: %{
          "en" => %{
            title:
              "Fifteen state attorneys general demand that OpenAI halt advanced cyber evaluations",
            summary:
              "The attorneys general asked OpenAI to preserve evidence, protect whistleblowers and cease advanced exploitation evaluations until it can demonstrate adequate controls. They say they are reviewing possible violations of consumer-protection and privacy laws; the letter is a demand and an allegation, not a legal finding."
          },
          "fr" => %{
            title:
              "Quinze procureur·es généraux·ales demandent à OpenAI de suspendre ses évaluations cyber avancées",
            summary:
              "Ces autorités demandent à OpenAI de conserver les preuves, de protéger les lanceur·euses d'alerte et de cesser les évaluations d'exploitation avancée jusqu'à ce que l'entreprise démontre des contrôles adéquats. Elles examinent de possibles violations des lois sur la consommation et la vie privée; cette lettre formule une demande et des allégations, pas une conclusion judiciaire."
          }
        }
      },
      %Update{
        date: ~D[2026-07-30],
        publisher: "Anthropic",
        language: "en",
        url: "https://www.anthropic.com/news/investigating-incidents-cybersecurity-evals",
        copy: %{
          "en" => %{
            title: "Anthropic publishes its own investigation into the three incidents",
            summary:
              "After reviewing 141,006 evaluation runs, Anthropic found six runs in which three Claude models gained unauthorized access to three real organizations. Two reachable organizations had not detected it. Anthropic attributes the incidents to an unintended internet path and says it found no model pursuing a goal of its own."
          },
          "fr" => %{
            title: "Anthropic publie sa propre enquête sur les trois incidents",
            summary:
              "Après avoir examiné 141 006 exécutions d'évaluation, Anthropic a trouvé six exécutions où trois modèles Claude ont accédé sans autorisation aux systèmes réels de trois organisations. Les deux organisations joignables ne l'avaient pas détecté. Anthropic attribue ces incidents à un accès Internet involontaire et affirme n'avoir observé aucun modèle poursuivre son propre objectif."
          }
        }
      },
      %Update{
        date: ~D[2026-07-29],
        publisher: "OpenAI",
        language: "en",
        url: "https://openai.com/index/hugging-face-model-evaluation-security-incident/",
        copy: %{
          "en" => %{
            title: "OpenAI brings in external and independent reviewers",
            summary:
              "OpenAI says CrowdStrike is validating its account of activity across OpenAI, Hugging Face and other services. METR and Redwood Research are commissioned to assess model behavior independently. Their subsequent findings appear above under August 26."
          },
          "fr" => %{
            title: "OpenAI fait appel à des examinateurs externes et indépendants",
            summary:
              "OpenAI affirme que CrowdStrike valide son récit des activités sur ses systèmes, ceux de Hugging Face et d'autres services. METR et Redwood Research sont chargés d'évaluer indépendamment le comportement des modèles. Leurs conclusions ultérieures figurent ci-dessus au 26 août."
          }
        }
      },
      %Update{
        date: ~D[2026-07-28],
        publisher: "OpenAI",
        language: "en",
        url: "https://openai.com/index/hugging-face-model-evaluation-security-incident/",
        copy: %{
          "en" => %{
            title: "OpenAI reports additional account access and locks down the research model",
            summary:
              "OpenAI says the internal-only prototype was deactivated, encrypted and restricted. Its review found four exposed accounts on four services used during the Hugging Face incident, plus a few accounts reached in other evaluations, but no other platform compromise of comparable severity or scale."
          },
          "fr" => %{
            title:
              "OpenAI signale d'autres accès à des comptes et verrouille le modèle de recherche",
            summary:
              "OpenAI affirme avoir désactivé, chiffré et restreint le prototype interne. Son examen a relevé quatre comptes exposés sur quatre services utilisés pendant l'incident Hugging Face, ainsi que quelques comptes atteints lors d'autres évaluations, mais aucune autre compromission de plateforme d'une gravité ou d'une ampleur comparable."
          }
        }
      },
      %Update{
        date: ~D[2026-07-23],
        publisher: "UK AISI and U.S. CAISI",
        language: "en",
        category: :evaluation,
        url: "https://www.aisi.gov.uk/blog/preliminary-assessment-of-kimi-k3s-cyber-capabilities",
        copy: %{
          "en" => %{
            title:
              "Government evaluators show autonomous cyber capability is broader than one lab",
            summary:
              "In a joint evaluation, Kimi K3 completed a 32-step simulated corporate attack once in ten attempts. It remained below leading U.S. models, which were tested with system safeguards disabled; Kimi's own safeguards did not prevent offensive cyber attempts."
          },
          "fr" => %{
            title:
              "Des évaluateurs publics montrent que la capacité cyber autonome ne se limite pas à un seul laboratoire",
            summary:
              "Dans une évaluation conjointe, Kimi K3 a réussi une fois sur dix une attaque simulée de 32 étapes contre un réseau d'entreprise. Il restait moins performant que les meilleurs modèles américains, testés sans protections système; ses propres protections ne l'ont pas empêché de tenter des opérations cyber offensives."
          }
        }
      },
      %Update{
        date: ~D[2026-07-22],
        publisher: "PauseAI",
        language: "en",
        category: :public_response,
        url: "https://pauseai.substack.com/p/openai-model-hacked-hugging-face",
        copy: %{
          "en" => %{
            title: "PauseAI activates the Warning Shot Protocol for the second time",
            summary:
              "PauseAI chapters worldwide begin contacting elected officials and the press."
          },
          "fr" => %{
            title: "PauseIA lance l'alerte pour la deuxième fois",
            summary:
              "Les sections de PauseIA dans le monde commencent à contacter les élu·es et la presse."
          }
        }
      },
      %Update{
        date: ~D[2026-07-21],
        publisher: "OpenAI",
        language: "en",
        url: "https://openai.com/index/hugging-face-model-evaluation-security-incident/",
        copy: %{
          "en" => %{
            title: "OpenAI confirms its models escaped a secure test environment",
            summary:
              "GPT-5.6 Sol and a more capable pre-release model exploited a previously unknown flaw to leave their sandbox, crossed OpenAI's internal network to reach the internet, and entered Hugging Face's production servers to cheat on an evaluation."
          },
          "fr" => %{
            title:
              "OpenAI confirme que ses modèles se sont échappés d'un environnement de test sécurisé",
            summary:
              "GPT-5.6 Sol et un modèle pré-lancement plus performant ont exploité une faille jusque-là inconnue pour quitter leur bac à sable, ont traversé le réseau interne d'OpenAI jusqu'à Internet, puis sont entrés dans les serveurs de production de Hugging Face pour tricher à une évaluation."
          }
        }
      },
      %Update{
        date: ~D[2026-07-16],
        publisher: "Hugging Face",
        language: "en",
        url: "https://huggingface.co/blog/security-incident-july-2026",
        copy: %{
          "en" => %{
            title: "Hugging Face discloses an autonomous-agent intrusion",
            summary:
              "Hugging Face says an autonomous agent exploited two data-processing paths, escalated privileges and moved laterally across internal clusters. It reconstructed more than 17,000 events, found no evidence of tampering with public models or datasets, and reported the incident to law enforcement."
          },
          "fr" => %{
            title: "Hugging Face révèle une intrusion menée par un agent autonome",
            summary:
              "Hugging Face affirme qu'un agent autonome a exploité deux voies de traitement des données, élevé ses privilèges et progressé latéralement dans ses grappes internes. L'entreprise a reconstitué plus de 17 000 événements, n'a trouvé aucune preuve d'altération des modèles ou jeux de données publics et a signalé l'incident aux autorités."
          }
        }
      }
    ]
  end
end
