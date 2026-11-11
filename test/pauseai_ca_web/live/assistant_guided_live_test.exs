defmodule PauseAiCaWeb.AssistantGuidedLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Assistant, GuidedModeFixtures, Repo}
  alias PauseAiCa.Assistant.GuidedMode, as: Guide

  defmodule HoldOutput do
    def review(request, _) do
      held = String.starts_with?(request["text"], "{")

      {:ok,
       %{
         risk: if(held, do: :review, else: :low),
         model: "synthetic-review",
         probabilities: %{"low" => if(held, do: 0.5, else: 1.0), "block" => 0.0}
       }}
    end
  end

  defmodule FailedAnchor do
    def status(_), do: %{audit_anchor: true, alerts: true}
    def confirm(_, _), do: {:error, :synthetic_anchor_failure}
  end

  setup do
    old = Application.fetch_env(:pauseai_ca, :agent_assistant)
    env = Map.new(["PAUSEAI_CA_RELEASE_ID", "PAUSEAI_CA_GIT_SHA"], &{&1, System.get_env(&1)})
    System.put_env("PAUSEAI_CA_RELEASE_ID", "guided-synthetic-fixture")
    System.put_env("PAUSEAI_CA_GIT_SHA", String.duplicate("a", 40))
    Application.put_env(:pauseai_ca, :agent_assistant, GuidedModeFixtures.configuration(self()))
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    assert {:ok, _} = Assistant.set_enabled(scope, true)
    token = Accounts.generate_user_session_token(admin)

    on_exit(fn ->
      case old do
        {:ok, v} -> Application.put_env(:pauseai_ca, :agent_assistant, v)
        :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
      end

      Enum.each(env, fn {k, v} -> if v, do: System.put_env(k, v), else: System.delete_env(k) end)
    end)

    %{admin: admin, scope: scope, token: token}
  end

  test "unrequested client acknowledgement and claimed URL/count cannot advance a guide", c do
    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive,
        session: %{"user_token" => c.token, "site_locale" => "en"}
      )

    render_click(view, "assistant-guide-observed", %{
      "token" => "forged",
      "url" => "/admin/contacts",
      "count" => 999
    })

    refute has_element?(view, "#site-assistant-guide")
    Phoenix.PubSub.subscribe(PauseAiCa.PubSub, Guide.topic(c.admin.id))
    {:ok, contacts, _} = live(log_in_user(c.conn, c.admin), "/admin/contacts?locale=en")

    render_click(contacts, "assistant-guided-observe", %{
      "token" => "synthetic-token",
      "url" => "/forged",
      "count" => 999
    })

    assert_receive {:guided_page_observed, observation}
    assert observation["count"] == 0
    assert URI.parse(observation["url"]).path == "/admin/contacts"
    refute observation["url"] == "/forged"
  end

  test "output review hold prevents interpreting otherwise valid JSON", c do
    config = Assistant.configuration()
    safety = Keyword.put(config[:safety], :jev, {HoldOutput, [api_key: "synthetic"]})
    Application.put_env(:pauseai_ca, :agent_assistant, Keyword.put(config, :safety, safety))

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive,
        session: %{"user_token" => c.token, "site_locale" => "en"}
      )

    render_click(view, "assistant-guided-mode", %{"enabled" => "true"})

    render_submit(view, "assistant-submit", %{
      "assistant" => %{"text" => "Show the configured area"}
    })

    render_async(view, 5_000)
    refute has_element?(view, "#site-assistant-guide")
    assert_received {:guided_provider_called, _}

    refute Repo.get_by(PhoenixAgentAssistant.Store.Stream,
             namespace: Assistant.store().namespace,
             actor_id: c.admin.id,
             reference: "guided-ui"
           )
  end

  test "unverified structured output retains the draft without executing a guide", c do
    config = Assistant.configuration()
    {provider, options} = config[:provider]

    config =
      Keyword.put(
        config,
        :provider,
        {provider, Keyword.put(options, :response_text, "Not a registered plan")}
      )

    Application.put_env(:pauseai_ca, :agent_assistant, config)

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive,
        session: %{"user_token" => c.token, "site_locale" => "en"}
      )

    render_click(view, "assistant-guided-mode", %{"enabled" => "true"})

    render_submit(view, "assistant-submit", %{
      "assistant" => %{"text" => "Keep this guide request"}
    })

    html = render_async(view, 5_000)
    assert html =~ "The guide could not be verified. Your message is retained."
    assert has_element?(view, "#site-assistant-text", "Keep this guide request")
    refute has_element?(view, "#site-assistant-guide")
    assert_received {:guided_provider_called, _}
    refute_received {:guided_provider_called, _}
  end

  test "Vancouver human step remains visible while waiting for an actual saved list", c do
    config = Assistant.configuration()

    feature = %{
      id: "crm-vancouver-guided",
      title: "Vancouver",
      summary: "Fixture",
      introduced_in: Application.spec(:pauseai_ca, :vsn) |> to_string(),
      entry_path: "/admin/contacts",
      enabled: true,
      ready: true,
      scenarios: ["CRM-UX-VAN-01-en", "CRM-UX-VAN-01-fr"]
    }

    config =
      config
      |> Keyword.update!(:features, &(&1 ++ [feature]))
      |> Keyword.update!(:feature_evidence, fn evidence ->
        update_in(
          evidence,
          [:results],
          &Map.merge(&1, %{"CRM-UX-VAN-01-en" => "success", "CRM-UX-VAN-01-fr" => "success"})
        )
      end)

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    {:ok, manifest, _} = Guide.manifest(c.scope, "en")
    text = PauseAiCa.Assistant.VancouverGuide.example_plan(manifest) |> Jason.encode!()
    {provider, options} = config[:provider]

    Application.put_env(
      :pauseai_ca,
      :agent_assistant,
      Keyword.put(config, :provider, {provider, Keyword.put(options, :response_text, text)})
    )

    {:ok, view, _} =
      live_isolated(c.conn, PauseAiCaWeb.AssistantLive,
        session: %{"user_token" => c.token, "site_locale" => "en"}
      )

    render_click(view, "assistant-guided-mode", %{"enabled" => "true"})

    render_submit(view, "assistant-submit", %{
      "assistant" => %{"text" => "Prepare the Vancouver city list"}
    })

    render_async(view, 5_000)
    assert has_element?(view, "#site-assistant-guide-step", "Step 1 of 5")
    assert has_element?(view, "#vancouver-guide-reference", "31 candidates")
    assert has_element?(view, "#vancouver-guide-reference", "recorded city Vancouver")

    for {cities, query} <- [{[], ""}, {["Vancouver"], "&cities[]=Vancouver"}] do
      render_click(view, "assistant-guide-next", %{})
      assert_push_event(view, "paa:guided-command", %{token: token})

      send(
        view.pid,
        {:guided_page_observed,
         %{
           "token" => token,
           "session" => Guide.session_fingerprint(c.token),
           "url" => "/admin/contacts?locale=en" <> query,
           "filters" => PauseAiCa.CRM.Geography.filters(%{"cities" => cities}),
           "count" => 999
         }}
      )

      render(view)
    end

    render_click(view, "assistant-guide-next", %{})
    assert_push_event(view, "paa:guided-command", %{token: token})

    send(
      view.pid,
      {:guided_page_observed,
       %{
         "token" => token,
         "session" => Guide.session_fingerprint(c.token),
         "url" => "/manage/lists?locale=en"
       }}
    )

    assert render(view) =~ "Step 4 of 5"
    render_click(view, "assistant-guide-next", %{})
    assert_push_event(view, "paa:guided-command", %{token: human_token, human_step: true})

    send(
      view.pid,
      {:guided_page_observed,
       %{
         "token" => human_token,
         "session" => Guide.session_fingerprint(c.token),
         "url" => "/manage/lists?locale=en"
       }}
    )

    assert render(view) =~ "Step 4 of 5"
    refute has_element?(view, "#site-assistant-guide-error")
    assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == 0
    assert_received {:guided_provider_called, _}
    refute_received {:guided_provider_called, _}
  end

  test "audit failure and demotion stop plan activation and every later action", c do
    {:ok, manifest, _} = Guide.manifest(c.scope, "en")
    text = Guide.example_plan(manifest, "toronto_gta") |> Jason.encode!()
    original = Assistant.configuration()
    config = Keyword.put(original, :operations_adapter, {FailedAnchor, []})
    Application.put_env(:pauseai_ca, :agent_assistant, config)
    assert {:error, _} = Guide.start(c.scope, text, "en", "one-session")
    Application.put_env(:pauseai_ca, :agent_assistant, original)
    assert {:ok, state} = Guide.start(c.scope, text, "en", "one-session")
    other = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    assert {:error, _} = Guide.next(Accounts.Scope.for_user(other), state, "en", "one-session")
    Repo.update!(Ecto.Changeset.change(c.admin, superadmin: false))
    assert {:error, _} = Guide.next(c.scope, state, "en", "one-session")
    refute_received {:guided_provider_called, _}
  end
end
