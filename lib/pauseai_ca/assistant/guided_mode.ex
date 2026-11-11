defmodule PauseAiCa.Assistant.GuidedMode do
  @moduledoc "Read-only host registration for reviewed Contacts guides. No contact mutation or mail action."
  alias PauseAiCa.{Accounts, Assistant, CRM, Repo}
  alias PauseAiCa.Assistant.VancouverGuide
  alias PhoenixAgentAssistant.{Canonical, Catalog, GuidedMode}
  @feature "crm-guided"
  @journey "crm.audience_preview"

  def manifest(scope, locale) when locale in ["en", "fr"] do
    with {:ok, fresh} <- authorized(scope),
         identity <- AcceptanceHarness.Health.payload(),
         source when is_binary(source) <- System.get_env("PAUSEAI_CA_GIT_SHA"),
         true <- Regex.match?(~r/\A[a-f0-9]{40}\z/, source),
         config <- Assistant.configuration(),
         feature when is_map(feature) <- Enum.find(config[:features] || [], &(&1.id == @feature)),
         %{status: status} when status in [:available, :new] <-
           Catalog.describe(feature, %{
             version: identity.version,
             build: identity.release_id,
             evidence: config[:feature_evidence] || %{}
           }) do
      controls = %{
        "menu.contacts" => %{"label" => "Contacts", "types" => ["activate_menu_item"]},
        "crm.geography.areas" => %{
          "label" => "Named areas",
          "types" => ["focus", "select_options"],
          "options" => Enum.map(CRM.Geography.catalogue()["areas"], & &1["id"])
        }
      }

      steps = [
        %{
          "id" => "open_contacts",
          "actions" => [%{"type" => "activate_menu_item", "control" => "menu.contacts"}]
        },
        %{
          "id" => "choose_area",
          "actions" => [
            %{"type" => "focus", "control" => "crm.geography.areas"},
            %{"type" => "select_options", "control" => "crm.geography.areas"}
          ]
        }
      ]

      registration = VancouverGuide.registration()
      vancouver? = feature_available?(config, identity, "crm-vancouver-guided")
      controls = if vancouver?, do: Map.merge(controls, registration.controls), else: controls
      journeys = %{@journey => %{"steps" => steps}}
      journeys = if vancouver?, do: Map.merge(journeys, registration.journeys), else: journeys

      metadata =
        %{
          "version" => identity.version,
          "build" => identity.release_id,
          "source" => source,
          "locale" => locale,
          "geography_version" => CRM.Geography.version()
        }

      metadata =
        if vancouver?,
          do: Map.put(metadata, "reference_digest", VancouverGuide.reference_digest()),
          else: metadata

      manifest =
        GuidedMode.manifest(
          metadata,
          controls,
          journeys
        )

      {:ok, manifest, fresh}
    else
      _ -> {:error, :guide_unavailable}
    end
  rescue
    _ -> {:error, :guide_unavailable}
  end

  def context(scope, locale) do
    with {:ok, manifest, _} <- manifest(scope, locale) do
      example = example_plan(manifest, hd(manifest["controls"]["crm.geography.areas"]["options"]))

      context = %{
        "manifest_json" => Jason.encode!(manifest),
        "example_json" => Jason.encode!(example),
        "instruction" =>
          "Return only one JSON object matching a registered journey example. Use the exact manifest_digest, ordered steps and registered controls. No URLs, selectors, code, extra fields, prose or tools. Choose one configured area for the read-only area journey. Human Save and Compose actions in the Vancouver journey must never be automated. Postal candidates are public reference evidence, not the city audience rule."
      }

      context =
        if Map.has_key?(manifest["journeys"], VancouverGuide.journey()),
          do:
            Map.put(
              context,
              "vancouver_example_json",
              Jason.encode!(VancouverGuide.example_plan(manifest))
            ),
          else: context

      {:ok, context}
    end
  end

  @doc false
  def example_plan(manifest, area) do
    steps = get_in(manifest, ["journeys", @journey, "steps"])

    %{
      "protocol_version" => 1,
      "manifest_digest" => manifest["digest"],
      "journey" => @journey,
      "steps" =>
        put_in(steps, [Access.at(1), "actions", Access.at(1), "arguments"], %{"values" => [area]})
    }
  end

  def start(scope, text, locale, session) do
    with {:ok, manifest, fresh} <- manifest(scope, locale),
         {:ok, plan} <- GuidedMode.parse(text, manifest),
         true <- valid_plan?(plan),
         :ok <- record(fresh, "guided_plan", manifest, %{"plan_digest" => Canonical.digest(plan)}) do
      state = GuidedMode.start(plan, binding(fresh, manifest, session), now())
      if vancouver?(plan), do: VancouverGuide.initialize(state, fresh), else: {:ok, state}
    else
      _ -> {:error, :guide_unavailable}
    end
  end

  def next(scope, state, locale, session) do
    with {:ok, manifest, fresh} <- manifest(scope, locale),
         {:ok, pending, %{token: token, step: step}} <-
           GuidedMode.next(state, binding(fresh, manifest, session), now()),
         :ok <- record(fresh, "guided_step_requested", manifest, %{"step" => step["id"]}) do
      if vancouver?(state.plan) do
        {:ok, pending, VancouverGuide.command(state, token, step, locale)}
      else
        actions =
          Enum.map(step["actions"], fn action ->
            target =
              if action["control"] == "menu.contacts",
                do: "manage-menu-navigation-pauseai.contacts",
                else: "crm-areas"

            %{
              type: action["type"],
              target_id: target,
              values: get_in(action, ["arguments", "values"])
            }
          end)

        {:ok, pending,
         %{
           token: token,
           actions: actions,
           expected_path: "/admin/contacts",
           locale: locale,
           expected_areas: if(state.index == 0, do: [], else: areas(state.plan))
         }}
      end
    else
      _ -> {:error, :guide_unavailable}
    end
  end

  def acknowledge(scope, state, observation, locale, session) do
    with {:ok, manifest, fresh} <- manifest(scope, locale),
         true <- is_binary(observation["token"]) && observation["token"] == state.token,
         true <- state.binding == binding(fresh, manifest, session),
         true <- now() < state.expires_at && not state.failed,
         true <- observation["session"] == state.binding.session.login,
         {:ok, verified, count} <- verify_observation(fresh, state, observation, locale),
         {:ok, advanced} <-
           GuidedMode.acknowledge(
             verified,
             binding(fresh, manifest, session),
             observation["token"],
             now()
           ),
         :ok <-
           record(fresh, "guided_step_verified", manifest, %{
             "step" => Enum.at(state.plan["steps"], state.index)["id"],
             "count" => count
           }) do
      {:ok, advanced, count}
    else
      :waiting -> {:waiting, state}
      {:handoff, waiting, command} -> {:waiting, waiting, command}
      _ -> {:error, :guide_unavailable}
    end
  end

  def back(scope, state, locale, session) do
    with {:ok, manifest, fresh} <- manifest(scope, locale),
         :ok <- record(fresh, "guided_back", manifest, %{}),
         do: GuidedMode.back(state, binding(fresh, manifest, session), now())
  end

  def exit(scope, locale) do
    with {:ok, manifest, fresh} <- manifest(scope, locale),
         do: record(fresh, "guided_exit", manifest, %{})
  end

  def failed(scope, locale, category) do
    with {:ok, manifest, fresh} <- manifest(scope, locale),
         true <- category in ~w(route control option action postcondition),
         do: record(fresh, "guided_step_failed", manifest, %{"category" => category}),
         else: (_ -> {:error, :guide_unavailable})
  end

  def observe(scope, token, uri, params, login) do
    with {:ok, fresh} <- authorized(scope),
         true <- is_binary(token) and byte_size(token) in 1..64,
         true <- is_binary(login) and byte_size(login) == 64,
         {:ok, page} <- CRM.directory_page(fresh, params) do
      observation = %{
        "token" => token,
        "session" => login,
        "url" => uri,
        "filters" => page.geography_filters,
        "q" => page.q,
        "region" => page.region,
        "count" => page.total
      }

      Phoenix.PubSub.broadcast(
        PauseAiCa.PubSub,
        topic(fresh.user.id),
        {:guided_page_observed, observation}
      )

      :ok
    else
      _ ->
        if match?(%{user: %{id: _}}, scope) and is_binary(token) and byte_size(token) <= 64 do
          Phoenix.PubSub.broadcast(
            PauseAiCa.PubSub,
            topic(scope.user.id),
            {:guided_page_observed, %{"token" => token, "unavailable" => true}}
          )
        end

        {:error, :guide_unavailable}
    end
  end

  def observe_list(scope, token, uri, login, list_id, draft_id \\ nil) do
    with {:ok, fresh} <- authorized(scope),
         true <- is_binary(token) and byte_size(token) in 1..64,
         true <- is_binary(login) and byte_size(login) == 64,
         {:ok, list} <- observed_list(fresh, list_id),
         {:ok, draft} <- observed_draft(fresh, draft_id) do
      observation = %{
        "token" => token,
        "session" => login,
        "url" => uri,
        "list_id" => list && list.id,
        "list_revision" => list && list.revision,
        "draft_id" => draft && draft.id
      }

      Phoenix.PubSub.broadcast(
        PauseAiCa.PubSub,
        topic(fresh.user.id),
        {:guided_page_observed, observation}
      )

      :ok
    else
      _ -> {:error, :guide_unavailable}
    end
  end

  defp observed_list(_, nil), do: {:ok, nil}
  defp observed_list(scope, id), do: PauseAiCa.Newsletters.Lists.get(scope, id)
  defp observed_draft(_, nil), do: {:ok, nil}
  defp observed_draft(scope, id), do: PauseAiCa.Newsletters.Drafts.get(scope, id)

  def area_label(%{"journey" => "crm.vancouver_workflow"}), do: "Vancouver"

  def area_label(plan) do
    selected = areas(plan)

    CRM.Geography.catalogue()["areas"]
    |> Enum.filter(&(&1["id"] in selected))
    |> Enum.map_join(", ", & &1["name"])
  end

  @doc false
  def session_fingerprint(token) when is_binary(token),
    do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)

  def session_fingerprint(_), do: nil

  def topic(actor), do: "assistant:guided:" <> actor

  defp vancouver?(plan), do: plan["journey"] == VancouverGuide.journey()

  defp valid_plan?(plan) do
    if vancouver?(plan), do: VancouverGuide.valid_plan?(plan), else: length(areas(plan)) == 1
  end

  defp verify_observation(scope, state, data, locale) do
    if vancouver?(state.plan) do
      VancouverGuide.verify(scope, state, data, locale)
    else
      if valid_observation?(state, data, locale), do: {:ok, state, data["count"]}, else: :error
    end
  end

  defp feature_available?(config, identity, id) do
    case Enum.find(config[:features] || [], &(&1.id == id)) do
      nil ->
        false

      feature ->
        Catalog.describe(feature, %{
          version: identity.version,
          build: identity.release_id,
          evidence: config[:feature_evidence] || %{}
        }).status in [:available, :new]
    end
  end

  defp valid_observation?(state, data, locale) do
    parsed = URI.parse(data["url"])
    params = Plug.Conn.Query.decode(parsed.query || "")
    expected = if state.index == 0, do: [], else: areas(state.plan)
    filters = data["filters"]

    is_binary(data["session"]) and data["session"] == state.binding.session.login and
      parsed.path == "/admin/contacts" and params["locale"] == locale and
      params["page"] in [nil, "1"] and params["per"] in [nil, "10", "25", "50", "100"] and
      (params["areas"] || []) == expected and
      Enum.all?(Map.keys(params), &(&1 in ~w(locale page per q region areas))) and
      CRM.Geography.filters(params) == filters and filters["areas"] == expected and
      Enum.all?(~w(provinces cities fsas), &(filters[&1] == [])) and filters["unknown"] == "false" and
      data["q"] == "" and data["region"] == "" and is_integer(data["count"]) and
      data["count"] >= 0
  rescue
    _ -> false
  end

  defp areas(plan),
    do: get_in(plan, ["steps", Access.at(1), "actions", Access.at(1), "arguments", "values"])

  defp authorized(%{user: %{id: id}}) do
    case Repo.get(Accounts.User, id) do
      %Accounts.User{confirmed_at: at, superadmin: true} = user when not is_nil(at) ->
        fresh = Accounts.Scope.for_user(user)
        if Assistant.visible?(fresh), do: {:ok, fresh}, else: {:error, :guide_unavailable}

      _ ->
        {:error, :guide_unavailable}
    end
  end

  defp authorized(_), do: {:error, :guide_unavailable}

  defp binding(scope, manifest, session),
    do: %{
      actor: scope.user.id,
      namespace: Assistant.store().namespace,
      manifest: manifest["digest"],
      session: session
    }

  defp record(scope, kind, manifest, data) do
    config = Assistant.configuration() |> Keyword.put(:conversation_ref, "guided-ui")

    Assistant.record(
      scope,
      Map.merge(data, %{"kind" => kind, "manifest_digest" => manifest["digest"]}),
      config
    )
  end

  defp now, do: System.monotonic_time(:second)
end
