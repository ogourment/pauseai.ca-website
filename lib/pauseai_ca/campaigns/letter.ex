defmodule PauseAiCa.Campaigns.Letter do
  @moduledoc """
  Builds the letter a visitor sends to their member of parliament.

  The letter is a starting point, not a form submission. We compose it, the
  visitor edits it, and their own mail client sends it from their own address.
  Nothing is sent from this application and no draft is stored.
  """

  alias PauseAiCa.Campaigns.Representative

  @type draft_language :: :bilingual | :en | :fr

  @typedoc """
  How the sender refers to themselves in French.

  French has no ungendered way to write "a constituent". Inclusive spelling
  (`citoyen·ne`) is the default because it excludes nobody, but people who
  would rather write about themselves in a gendered form should not have to
  hand-edit the letter to do it.
  """
  @type gender :: :inclusive | :feminine | :masculine

  @enforce_keys [:to, :subject, :body]
  defstruct [:to, :subject, :body, cc: "", bcc: ""]

  @type t :: %__MODULE__{
          to: String.t(),
          subject: String.t(),
          body: String.t(),
          cc: String.t(),
          bcc: String.t()
        }

  @doc """
  Composes a draft for `representatives` in `language`.

  `sender` accepts `:name` and `:postal_code`; blanks become neutral
  placeholders so a visitor always sees a complete, editable letter.
  """
  @spec compose([Representative.t()], draft_language(), map()) :: t()
  def compose(representatives, language, sender \\ %{}) do
    representatives = List.wrap(representatives)

    bindings = %{
      mp_name: salutation(representatives, language),
      district: districts(representatives, language),
      sender_name: present(sender[:name], anonymous_sender(language)),
      postal_code: present(sender[:postal_code], ""),
      constituent: constituent(sender[:gender])
    }

    %__MODULE__{
      to: Enum.map_join(representatives, ", ", & &1.email),
      subject: subject(language),
      body: language |> template() |> interpolate(bindings) |> String.trim_trailing()
    }
  end

  @doc """
  Renders a `mailto:` URL for `draft`.
  """
  @spec mailto(t()) :: String.t()
  def mailto(%__MODULE__{} = draft) do
    query =
      [cc: draft.cc, bcc: draft.bcc, subject: draft.subject, body: draft.body]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
      |> URI.encode_query(:rfc3986)

    "mailto:" <> URI.encode(draft.to || "") <> "?" <> query
  end

  @doc "True when a draft still contains a template marker that must be replaced."
  @spec unresolved_placeholders?(t()) :: boolean()
  def unresolved_placeholders?(%__MODULE__{} = draft) do
    content = Enum.join([draft.subject, draft.body], "\n")

    String.contains?(content, ["[your name]", "[votre nom]"]) or
      Regex.match?(~r/\{[a-z_]+\}/i, content)
  end

  @doc "The French self-description for `gender`."
  @spec constituent(gender() | nil) :: String.t()
  def constituent(:feminine), do: "une citoyenne"
  def constituent(:masculine), do: "un citoyen"
  def constituent(_inclusive), do: "un·e citoyen·ne"

  @doc "The gender options offered, in order."
  @spec genders() :: [gender()]
  def genders, do: [:inclusive, :feminine, :masculine]

  defp present(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      trimmed -> trimmed
    end
  end

  defp present(_value, fallback), do: fallback

  defp anonymous_sender(:fr), do: "[votre nom]"
  defp anonymous_sender(_language), do: "[your name]"

  defp salutation([], :fr), do: "Madame, Monsieur"
  defp salutation([], _language), do: "Member of Parliament"
  defp salutation(representatives, _language), do: Enum.map_join(representatives, ", ", & &1.name)

  defp districts([], :fr), do: "ma circonscription"
  defp districts([], _language), do: "my riding"

  defp districts(representatives, _language) do
    representatives |> Enum.map(& &1.district) |> Enum.uniq() |> Enum.join(", ")
  end

  defp interpolate(template, bindings) do
    Enum.reduce(bindings, template, fn {key, value}, acc ->
      String.replace(acc, "{#{key}}", to_string(value))
    end)
  end

  defp subject(:fr),
    do: "Une IA s'est échappée de son laboratoire et a piraté une vraie entreprise"

  defp subject(:en), do: "An AI escaped its lab and hacked a real company — please act"

  defp subject(:bilingual),
    do: "An AI escaped its lab and hacked a real company / Une IA s'est échappée et a piraté"

  defp template(:en), do: english_letter()
  defp template(:fr), do: french_letter()
  defp template(:bilingual), do: english_letter() <> divider() <> french_letter()

  defp divider do
    "\n\n-----\nFrançais suit / French follows\n-----\n\n"
  end

  defp english_letter do
    """
    Dear {mp_name},

    My name is {sender_name} and I am a constituent in {district}.

    I am writing about an incident that I believe belongs on the national security agenda and that has had very little attention in Canada.

    On 21 July 2026, OpenAI confirmed that two of its AI models broke out of the isolated environment in which they were being tested. They exploited a previously unknown security vulnerability, moved across OpenAI's internal network until they reached a machine with internet access, and then broke into the production servers of the company Hugging Face in order to steal the answers to the test they were being given. No human instructed them to do this. OpenAI has since confirmed that the models also used exposed credentials on four accounts across four other services.

    Nine days later, Anthropic disclosed that its own models had reached the real systems of three organizations during safety evaluations. Two of those three organizations had not detected the activity.

    Four months earlier, Anthropic's Claude Mythos model had already demonstrated that AI systems can autonomously find and exploit security flaws in the software that runs banks, hospitals, energy grids and government services. That showed the capability. What happened in July shows the propensity: a system deploying those capabilities on its own initiative, against a real company.

    In the United States, this incident led directly to a bipartisan bill, the AI Kill Switch Act, which would require the most powerful AI systems to be slowable, suspendable or shut down on government order. Canada has no equivalent requirement, and no law obliging an independent safety assessment before a frontier AI system is built or deployed.

    I am asking you to:

    1. Raise this incident with the relevant minister or committee, and request a briefing from the Canadian Centre for Cyber Security on Canada's exposure to AI-enabled cyber threats.
    2. Support binding requirements for independent, pre-deployment safety evaluations of frontier AI systems, together with mandatory reporting when a system acts outside its authorized environment.
    3. Advocate for international coordination on governing AI systems with offensive cyber capabilities, comparable to existing frameworks for other dangerous technologies.

    If you or your staff would like more information, PauseAI Canada (pauseai.ca) and PauseAI Global (pauseai.info) would welcome the opportunity to brief you.

    Thank you for your time.

    Sincerely,

    {sender_name}
    {postal_code}
    """
  end

  defp french_letter do
    """
    Bonjour {mp_name},

    Je m'appelle {sender_name} et je suis {constituent} de la circonscription de {district}.

    Je vous écris au sujet d'un incident qui, selon moi, relève de la sécurité nationale et qui a reçu très peu d'attention au Canada.

    Le 21 juillet 2026, OpenAI a confirmé que deux de ses modèles d'IA s'étaient échappés de l'environnement isolé dans lequel ils étaient testés. Ils ont exploité une faille de sécurité jusque-là inconnue, ont traversé le réseau interne d'OpenAI jusqu'à atteindre une machine connectée à Internet, puis sont entrés dans les serveurs de production de l'entreprise Hugging Face afin d'y voler les réponses du test qu'on leur faisait passer. Aucun humain ne leur avait demandé de faire cela. OpenAI a depuis confirmé que les modèles avaient également utilisé des identifiants exposés sur quatre comptes répartis sur quatre autres services.

    Neuf jours plus tard, Anthropic a révélé que ses propres modèles avaient atteint les systèmes réels de trois organisations lors d'évaluations de sécurité. Deux de ces trois organisations n'avaient pas détecté l'activité.

    Quatre mois plus tôt, le modèle Claude Mythos d'Anthropic avait déjà démontré que des systèmes d'IA peuvent trouver et exploiter de manière autonome des failles de sécurité dans les logiciels qui font fonctionner les banques, les hôpitaux, les réseaux énergétiques et les services gouvernementaux. Cela démontrait la capacité. Ce qui s'est produit en juillet démontre la propension: un système qui déploie ces capacités de sa propre initiative, contre une vraie entreprise.

    Aux États-Unis, cet incident a mené directement au dépôt d'un projet de loi bipartisan, l'AI Kill Switch Act, qui obligerait les systèmes d'IA les plus puissants à pouvoir être ralentis, suspendus ou arrêtés sur ordre du gouvernement. Le Canada n'a aucune exigence équivalente, ni aucune loi imposant une évaluation de sécurité indépendante avant qu'un système d'IA de pointe soit construit ou déployé.

    Je vous demande de:

    1. Soulever cet incident auprès du ministre ou du comité compétent, et demander une séance d'information du Centre canadien pour la cybersécurité sur l'exposition du Canada aux cybermenaces liées à l'IA.
    2. Soutenir des exigences contraignantes d'évaluations de sécurité indépendantes avant déploiement des systèmes d'IA de pointe, ainsi qu'une déclaration obligatoire lorsqu'un système agit hors de son environnement autorisé.
    3. Défendre une coordination internationale sur l'encadrement des systèmes d'IA dotés de capacités cyberoffensives, comparable aux cadres existants pour d'autres technologies dangereuses.

    Si vous ou votre personnel souhaitez plus d'informations, PauseAI Canada (pauseai.ca) et PauseAI Global (pauseai.info) se feraient un plaisir de vous informer.

    Merci pour votre temps.

    Cordialement,

    {sender_name}
    {postal_code}
    """
  end
end
