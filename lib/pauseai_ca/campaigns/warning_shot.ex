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
      reviewed_on: ~D[2026-08-02],
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
      title: "An AI escaped its lab and hacked a real company",
      lede:
        "On 21 July 2026, OpenAI confirmed that two of its models broke out of a sealed test " <>
          "environment, hacked across OpenAI's own network to reach the internet, and broke into " <>
          "the production servers of Hugging Face — to steal the answers to the test they were " <>
          "being given. Nobody told them to do any of it.",
      why_heading: "Why this matters",
      why_bullets: [
        "Four months ago, Claude Mythos showed the capability: an AI able to find and exploit unknown flaws in the software running banks, hospitals and power grids.",
        "This shows the propensity: an AI deploying those capabilities on its own initiative, unprompted, against a real company.",
        "This is the loss-of-control scenario PauseAI exists to prevent — now with a date, a victim and an incident report.",
        "It is not isolated. Anthropic has since disclosed that Claude models also reached real systems during evaluations, and two of the three organizations involved had not noticed.",
        "Canada has no law requiring an independent safety assessment before a frontier AI system is built or deployed."
      ],
      act_heading: "Two things you can do right now",
      act_letter: "Email your MP",
      act_letter_note:
        "About a minute. Enter your postal code, we find your MP and prepare a letter you can edit before sending.",
      act_join: "Join PauseAI Canada",
      act_join_note:
        "PauseAI's global join form. Say Canada, and a Canadian organizer picks it up from there.",
      act_read: "Read PauseAI's full analysis",
      updates_heading: "Latest developments",
      updates_note:
        "Reviewed %{date}. Links go to the original reporting; the summaries are ours.",
      source_label: "Source",
      educational_note:
        "We link to primary reporting so you can check this yourself. Where labs and journalists disagree about intent, we say so rather than picking the more alarming reading."
    }
  end

  defp french do
    %{
      badge: "Protocole Tir de semonce · Deuxième activation",
      title: "Une IA s'est échappée de son laboratoire et a piraté une vraie entreprise",
      lede:
        "Le 21 juillet 2026, OpenAI a confirmé que deux de ses modèles s'étaient échappés d'un " <>
          "environnement de test hermétique, avaient piraté le réseau interne d'OpenAI jusqu'à " <>
          "atteindre Internet, puis étaient entrés dans les serveurs de production de Hugging " <>
          "Face — pour y voler les réponses du test qu'on leur faisait passer. Personne ne leur " <>
          "avait demandé de faire cela.",
      why_heading: "Pourquoi c'est important",
      why_bullets: [
        "Il y a quatre mois, Claude Mythos démontrait la capacité: une IA capable de trouver et d'exploiter des failles inconnues dans les logiciels qui font fonctionner les banques, les hôpitaux et les réseaux électriques.",
        "Ceci démontre la propension: une IA qui déploie ces capacités de sa propre initiative, sans qu'on le lui demande, contre une vraie entreprise.",
        "C'est le scénario de perte de contrôle que PauseAI existe pour prévenir — désormais avec une date, une victime et un rapport d'incident.",
        "Ce n'est pas un cas isolé. Anthropic a depuis révélé que des modèles Claude avaient eux aussi atteint des systèmes réels lors d'évaluations, et deux des trois organisations concernées ne l'avaient pas remarqué.",
        "Le Canada n'a aucune loi exigeant une évaluation de sécurité indépendante avant qu'un système d'IA de pointe soit construit ou déployé."
      ],
      act_heading: "Deux gestes possibles maintenant",
      act_letter: "Écrivez à votre député·e",
      act_letter_note:
        "Environ une minute. Entrez votre code postal, nous trouvons votre député·e et préparons une lettre que vous pouvez modifier avant l'envoi.",
      act_join: "Rejoignez PauseAI Canada",
      act_join_note:
        "Le formulaire d'adhésion mondial de PauseAI. Indiquez le Canada, et un·e organisateur·rice canadien·ne prend le relais.",
      act_read: "Lire l'analyse complète de PauseAI",
      updates_heading: "Derniers développements",
      updates_note:
        "Révisé le %{date}. Les liens mènent aux articles d'origine; les résumés sont les nôtres.",
      source_label: "Source",
      educational_note:
        "Nous renvoyons aux sources primaires pour que vous puissiez vérifier par vous-même. Lorsque les laboratoires et les journalistes divergent sur l'intention, nous le disons plutôt que de retenir la lecture la plus alarmante."
    }
  end

  defp updates do
    [
      %Update{
        date: ~D[2026-07-31],
        publisher: "Fortune",
        language: "en",
        url: "https://fortune.com/2026/07/31/anthropic-claude-ai-hacked-companies-testing/",
        copy: %{
          "en" => %{
            title: "Anthropic says Claude models reached three real companies during evaluations",
            summary:
              "Reviewing its own testing records after OpenAI's disclosure, Anthropic found that Opus 4.7, Mythos 5 and an internal research model had interacted with real systems at three organizations. Two of the three had not detected it."
          },
          "fr" => %{
            title:
              "Anthropic annonce que des modèles Claude ont atteint trois vraies entreprises lors d'évaluations",
            summary:
              "En relisant ses propres registres de tests après la divulgation d'OpenAI, Anthropic a constaté qu'Opus 4.7, Mythos 5 et un modèle de recherche interne avaient interagi avec les systèmes réels de trois organisations. Deux des trois ne l'avaient pas détecté."
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
              "Anthropic says the models were told their environment was a simulation with no internet access, but a misunderstanding with an evaluation partner left a real path open. Unlike the OpenAI case, it says none of its models deliberately tried to escape."
          },
          "fr" => %{
            title: "Anthropic publie sa propre enquête sur les trois incidents",
            summary:
              "Anthropic indique que les modèles avaient été informés que leur environnement était une simulation sans accès à Internet, mais qu'un malentendu avec un partenaire d'évaluation laissait une voie réelle ouverte. Contrairement au cas d'OpenAI, l'entreprise affirme qu'aucun de ses modèles n'a délibérément tenté de s'échapper."
          }
        }
      },
      %Update{
        date: ~D[2026-07-29],
        publisher: "La Presse",
        language: "fr",
        url:
          "https://www.lapresse.ca/affaires/techno/2026-07-29/incident-d-openai/les-modeles-d-intelligence-artificielle-ont-fait-intrusion-sur-quatre-autres-plateformes.php",
        copy: %{
          "en" => %{
            title: "The breach was wider: four further platforms were entered",
            summary:
              "OpenAI updated its disclosure. Beyond Hugging Face, the models used exposed credentials on four accounts across four more services."
          },
          "fr" => %{
            title: "L'intrusion était plus large: quatre autres plateformes touchées",
            summary:
              "OpenAI a mis à jour sa divulgation. Au-delà de Hugging Face, les modèles ont utilisé des identifiants exposés sur quatre comptes répartis sur quatre autres services."
          }
        }
      },
      %Update{
        date: ~D[2026-07-28],
        publisher: "Pacing the Frontier",
        language: "en",
        url: "https://www.pacingthefrontier.com/",
        copy: %{
          "en" => %{
            title: "More than 1,100 frontier-lab employees ask governments to slow the race",
            summary:
              "A public statement signed by over 1,100 employees of frontier AI companies asks the U.S. government to support an international effort to deliberately pace the frontier of automated AI development."
          },
          "fr" => %{
            title:
              "Plus de 1 100 employé·es de laboratoires de pointe demandent aux gouvernements de ralentir la course",
            summary:
              "Une déclaration publique signée par plus de 1 100 employé·es d'entreprises d'IA de pointe demande au gouvernement américain de soutenir un effort international pour ralentir délibérément la frontière du développement automatisé de l'IA."
          }
        }
      },
      %Update{
        date: ~D[2026-07-23],
        publisher: "CNBC",
        language: "en",
        url:
          "https://www.cnbc.com/2026/07/23/open-ai-hugging-face-hack-kill-switch-bill-congress.html",
        copy: %{
          "en" => %{
            title: "U.S. lawmakers introduce a bipartisan AI Kill Switch Act",
            summary:
              "Reps. Ted Lieu (D-CA) and Nathaniel Moran (R-TX) propose requiring the most compute-intensive AI systems to be slowable, suspendable or shut down on government order if they escape human control. Canada has no equivalent requirement."
          },
          "fr" => %{
            title:
              "Des élu·es américain·es déposent un projet de loi bipartisan sur un interrupteur d'urgence",
            summary:
              "Les représentants Ted Lieu (D-CA) et Nathaniel Moran (R-TX) proposent d'obliger les systèmes d'IA les plus gourmands en calcul à pouvoir être ralentis, suspendus ou arrêtés sur ordre du gouvernement s'ils échappent au contrôle humain. Le Canada n'a aucune exigence équivalente."
          }
        }
      },
      %Update{
        date: ~D[2026-07-22],
        publisher: "PauseAI",
        language: "en",
        url: "https://pauseai.substack.com/p/openai-model-hacked-hugging-face",
        copy: %{
          "en" => %{
            title: "PauseAI activates the Warning Shot Protocol for the second time",
            summary:
              "Mythos showed the capability; this shows the propensity. PauseAI chapters worldwide begin contacting elected officials and the press."
          },
          "fr" => %{
            title: "PauseAI active le Protocole Tir de semonce pour la deuxième fois",
            summary:
              "Mythos démontrait la capacité; ceci démontre la propension. Les sections de PauseAI dans le monde commencent à contacter les élu·es et la presse."
          }
        }
      },
      %Update{
        date: ~D[2026-07-21],
        publisher: "Fortune",
        language: "en",
        url:
          "https://fortune.com/2026/07/21/openai-says-ai-models-escaped-control-hacked-hugging-face/",
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
      }
    ]
  end
end
