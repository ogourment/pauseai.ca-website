defmodule PauseAiCa.Assistant.MPGuide do
  @moduledoc "Deterministic, supporter-owned MP walkthrough. It performs no lookup, edit, delivery or generation."
  alias PauseAiCa.{Accounts, Repo}
  alias PauseAiCa.Accounts.User
  alias PauseAiCa.Engagement.Action
  alias PhoenixAgentAssistant.GuidedMode
  alias PauseAiCaWeb.Endpoint
  @salt "supporter MP guide session v1"

  def context(assigns) do
    letter = assigns[:letter]

    ready =
      match?(%PauseAiCa.Campaigns.Letter{}, letter) and
        is_binary(letter.subject) and String.trim(letter.subject) != "" and
        is_binary(letter.body) and String.trim(letter.body) != "" and
        String.length(letter.body) <= 8_000 and
        not PauseAiCa.Campaigns.Letter.unresolved_placeholders?(letter)

    %{
      lookup_ready: is_list(assigns[:representatives]) and assigns[:representatives] != [],
      letter_ready: ready,
      send_state: assigns[:send_state],
      completed_action_id: assigns[:mp_completed_action_id]
    }
  end

  def enabled?, do: Application.get_env(:pauseai_ca, :mp_guide_enabled, false) == true

  def session(session) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)

    %{
      proof: Phoenix.Token.sign(Endpoint, @salt, nonce),
      nonce: nonce,
      token: session["user_token"]
    }
  end

  def actor(scope, session) do
    with true <- enabled?(),
         {:ok, nonce} <- Phoenix.Token.verify(Endpoint, @salt, session.proof, max_age: 3600),
         true <- nonce == session.nonce,
         {user, _} <- Accounts.get_user_by_session_token(session.token),
         %{user: %{id: id}} <- scope,
         true <- user.id == id,
         %User{confirmed_at: %DateTime{}} = fresh <- Repo.get(User, id) do
      {:ok, fresh}
    else
      _ -> {:error, :sign_in_required}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def start(scope, session, locale, uri) do
    with {:ok, user} <- actor(scope, session),
         true <- valid_route?(uri, locale) do
      manifest = manifest(locale)
      steps = manifest["journeys"]["mp.personal_letter"]["steps"]

      plan = %{
        "protocol_version" => 1,
        "manifest_digest" => manifest["digest"],
        "journey" => "mp.personal_letter",
        "steps" => steps
      }

      {:ok, plan} = GuidedMode.parse(Jason.encode!(plan), manifest)
      {:ok, GuidedMode.start(plan, binding(user, session, manifest), now())}
    else
      _ -> {:error, :guide_unavailable}
    end
  end

  def next(scope, session, locale, uri, state) do
    with {:ok, user} <- actor(scope, session),
         true <- valid_route?(uri, locale),
         {:ok, pending, %{token: token, step: step}} <-
           GuidedMode.next(state, binding(user, session, manifest(locale)), now()) do
      target =
        %{
          "lookup" => "participation_postal_code",
          "editor" => "letter_body",
          "review" => "send-letter"
        }[step["id"]]

      {:ok, pending,
       %{
         token: token,
         actions: [%{type: "focus", target_id: target}],
         expected_path: path(locale),
         human_step: true
       }}
    else
      _ -> {:error, :guide_unavailable}
    end
  end

  def observe(scope, session, locale, uri, state, context) do
    with {:ok, user} <- actor(scope, session),
         true <- valid_route?(uri, locale),
         true <- postcondition?(state.index, context, user),
         {:ok, advanced} <-
           GuidedMode.acknowledge(
             state,
             binding(user, session, manifest(locale)),
             state.token,
             now()
           ) do
      {:ok, advanced}
    else
      false -> {:waiting, state}
      _ -> {:error, :guide_unavailable}
    end
  end

  def back(scope, session, locale, uri, state) do
    with {:ok, user} <- actor(scope, session),
         true <- valid_route?(uri, locale),
         do: GuidedMode.back(state, binding(user, session, manifest(locale)), now())
  end

  def path("fr"), do: "/fr/contacter-votre-depute"
  def path(_), do: "/en/contact-your-mp"

  defp postcondition?(0, context, _), do: Map.get(context, :lookup_ready) == true
  defp postcondition?(1, context, _), do: Map.get(context, :letter_ready) == true

  defp postcondition?(2, %{send_state: :sent, completed_action_id: id}, user)
       when is_binary(id) do
    case Repo.get_by(Action, id: id, user_id: user.id) do
      %Action{action_type: "contacted_representative", confirmed_at: %DateTime{}} -> true
      _ -> false
    end
  end

  defp postcondition?(_, _, _), do: false

  defp valid_route?(uri, locale) when is_binary(uri) and locale in ["en", "fr"],
    do: URI.parse(uri).path == path(locale)

  defp valid_route?(_, _), do: false

  defp manifest(locale) do
    steps =
      Enum.map(
        ~w(lookup editor review),
        &%{"id" => &1, "actions" => [%{"type" => "focus", "control" => "mp." <> &1}]}
      )

    controls = Map.new(~w(lookup editor review), &{"mp." <> &1, %{"types" => ["focus"]}})

    GuidedMode.manifest(
      %{
        "version" => Application.spec(:pauseai_ca, :vsn) |> to_string(),
        "source" => System.get_env("PAUSEAI_CA_GIT_SHA"),
        "build" => System.get_env("PAUSEAI_CA_RELEASE_ID"),
        "locale" => locale
      },
      controls,
      %{"mp.personal_letter" => %{"steps" => steps}}
    )
  end

  defp binding(user, session, manifest),
    do: %{actor: user.id, session: session.proof, manifest: manifest["digest"]}

  defp now, do: System.monotonic_time(:second)
end
