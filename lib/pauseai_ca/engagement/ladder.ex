defmodule PauseAiCa.Engagement.Ladder do
  @moduledoc """
  A deliberately small engagement ladder. It recommends the next attainable
  contribution; it is guidance, not a score or a judgment about a person.
  """

  @levels [
    {:learn, ~w(learned)},
    {:talk, ~w(conversation)},
    {:show_up, ~w(event signed joined)},
    {:influence, ~w(contacted_representative met_representative)},
    {:contribute, ~w(flyered volunteered)},
    {:organize, ~w(organized)}
  ]

  def steps("fr") do
    [
      %{title: "Comprendre", examples: "Lire, regarder ou écouter une ressource fiable"},
      %{title: "En parler", examples: "Discuter des risques de l'IA avec une personne"},
      %{
        title: "Participer",
        examples: "Signer, rejoindre le mouvement ou assister à un événement"
      },
      %{title: "Intervenir", examples: "Contacter ou rencontrer une personne élue"},
      %{
        title: "Contribuer",
        examples: "Faire du bénévolat, distribuer des dépliants ou poser des affiches"
      },
      %{title: "Organiser", examples: "Créer une activité ou lancer un groupe local"}
    ]
  end

  def steps(_locale) do
    [
      %{title: "Learn", examples: "Read, watch, or listen to one reliable resource"},
      %{title: "Talk", examples: "Discuss AI risk with one person"},
      %{title: "Show up", examples: "Sign, join the movement, or attend an event"},
      %{title: "Influence", examples: "Contact or meet an elected representative"},
      %{title: "Contribute", examples: "Volunteer, flyer, or put up posters"},
      %{title: "Organize", examples: "Run an activity or start a local group"}
    ]
  end

  def position(actions) do
    Enum.reduce(actions, 0, fn action, highest ->
      case Enum.find_index(@levels, fn {_level, types} -> action.action_type in types end) do
        nil -> highest
        index -> max(highest, index + 1)
      end
    end)
  end

  def counts(by_type) do
    counts = Map.new(by_type)

    Enum.map(@levels, fn {_level, types} -> Enum.sum(Enum.map(types, &Map.get(counts, &1, 0))) end)
  end

  def recommendation(actions, locale) do
    completed = MapSet.new(Enum.map(actions, & &1.action_type))

    level =
      Enum.find_value(@levels, :organize, fn {level, types} ->
        if Enum.all?(types, &(not MapSet.member?(completed, &1))), do: level
      end)

    copy(level, locale)
  end

  defp copy(:learn, "fr"),
    do: %{
      title: "Comprendre un argument",
      why: "Commencez par une source fiable en français.",
      effort: "10 à 20 min",
      href: "/fr/comprendre",
      cta: "Choisir une ressource"
    }

  defp copy(:talk, "fr"),
    do: %{
      title: "En parler à une personne",
      why: "Une conversation permet de tester votre compréhension et d'entendre ses questions.",
      effort: "15 min",
      href: "/fr/comprendre",
      cta: "Trouver une ressource à partager"
    }

  defp copy(:show_up, "fr"),
    do: %{
      title: "Participer à une action",
      why: "Passer de l'intérêt à une action visible aide le mouvement à grandir.",
      effort: "30 min",
      href: "/fr/tir-de-semonce",
      cta: "Écrire à ma députée ou mon député"
    }

  defp copy(:influence, "fr"),
    do: %{
      title: "Contacter une personne élue",
      why:
        "Les responsables politiques prêtent attention aux demandes personnelles de leurs électeurs.",
      effort: "10 min",
      href: "/fr/tir-de-semonce",
      cta: "Préparer un message"
    }

  defp copy(:contribute, "fr"),
    do: %{
      title: "Aider l'équipe",
      why: "Votre temps peut transformer une campagne ponctuelle en capacité durable.",
      effort: "1 h",
      href: "https://pauseia.fr/agir",
      cta: "Voir comment contribuer"
    }

  defp copy(:organize, "fr"),
    do: %{
      title: "Rassembler d'autres personnes",
      why: "Les groupes locaux transforment des soutiens isolés en force collective.",
      effort: "1 à 2 h",
      href: "https://pauseia.fr/agir",
      cta: "Préparer une activité"
    }

  defp copy(:learn, _),
    do: %{
      title: "Understand one argument",
      why: "Start with one reliable source and note what remains unclear.",
      effort: "10–20 min",
      href: "/en/learn",
      cta: "Choose a resource"
    }

  defp copy(:talk, _),
    do: %{
      title: "Talk with one person",
      why: "A conversation tests your understanding and surfaces real questions.",
      effort: "15 min",
      href: "/en/learn",
      cta: "Find something to share"
    }

  defp copy(:show_up, _),
    do: %{
      title: "Take part in a campaign",
      why: "A visible action turns private concern into public support.",
      effort: "30 min",
      href: "/en/warning-shot",
      cta: "Write to my MP"
    }

  defp copy(:influence, _),
    do: %{
      title: "Contact an elected representative",
      why: "Representatives pay attention to personal requests from constituents.",
      effort: "10 min",
      href: "/en/warning-shot",
      cta: "Prepare a message"
    }

  defp copy(:contribute, _),
    do: %{
      title: "Help the team",
      why: "Your time can turn a one-off campaign into lasting capacity.",
      effort: "1 hour",
      href: "/act/join?locale=en",
      cta: "Find a way to contribute"
    }

  defp copy(:organize, _),
    do: %{
      title: "Bring people together",
      why: "Local groups turn isolated supporters into collective capacity.",
      effort: "1–2 hours",
      href: "/act/actions?locale=en",
      cta: "Plan an activity"
    }
end
