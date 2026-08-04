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
      reviewed_on: ~D[2026-08-04],
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
      updates_note: "Updated %{date}.",
      source_label: "Source",
      educational_note: nil
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
      updates_note: "Mis à jour le %{date}.",
      source_label: "Source",
      educational_note: nil
    }
  end

  defp updates do
    [
      %Update{
        date: ~D[2026-08-03],
        publisher: "Fifteen U.S. state attorneys general",
        language: "en",
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
              "OpenAI says CrowdStrike is validating its account of activity across OpenAI, Hugging Face and other services. METR and Redwood Research are conducting a separate assessment of the models' behaviour and are expected to publish their scope and findings."
          },
          "fr" => %{
            title: "OpenAI fait appel à des examinateurs externes et indépendants",
            summary:
              "OpenAI affirme que CrowdStrike valide son récit des activités sur ses systèmes, ceux de Hugging Face et d'autres services. METR et Redwood Research mènent une évaluation distincte du comportement des modèles et doivent en publier la portée et les conclusions."
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
              "OpenAI affirme avoir désactivé, chiffré et restreint le prototype interne. Son examen a relevé quatre comptes exposés sur quatre services utilisés pendant l'incident Hugging Face, ainsi que quelques comptes atteints lors d'autres évaluations, mais aucun autre compromis de plateforme d'une gravité ou d'une ampleur comparable."
          }
        }
      },
      %Update{
        date: ~D[2026-07-23],
        publisher: "UK AISI and U.S. CAISI",
        language: "en",
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
              "Des évaluateurs publics montrent que la capacité cyber autonome dépasse un seul laboratoire",
            summary:
              "Dans une évaluation conjointe, Kimi K3 a réussi une fois sur dix une attaque simulée de 32 étapes contre un réseau d'entreprise. Il restait moins performant que les meilleurs modèles américains, testés sans protections système; ses propres protections ne l'ont pas empêché de tenter des opérations cyber offensives."
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
