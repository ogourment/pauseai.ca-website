defmodule PauseAiCa.Assistant.VancouverGuideTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Assistant, CRM, GuidedModeFixtures, Repo}
  alias PauseAiCa.Assistant.{GuidedMode, VancouverGuide}
  alias PauseAiCa.Newsletters.{Drafts, Lists}

  setup do
    previous = Application.fetch_env(:pauseai_ca, :agent_assistant)
    old_build = System.get_env("PAUSEAI_CA_RELEASE_ID")
    old_source = System.get_env("PAUSEAI_CA_GIT_SHA")
    System.put_env("PAUSEAI_CA_RELEASE_ID", "guided-synthetic-fixture")
    System.put_env("PAUSEAI_CA_GIT_SHA", String.duplicate("a", 40))
    config = GuidedModeFixtures.configuration(self())

    feature = %{
      id: "crm-vancouver-guided",
      title: "Vancouver workflow",
      summary: "Synthetic guide",
      introduced_in: Application.spec(:pauseai_ca, :vsn) |> to_string(),
      entry_path: "/admin/contacts",
      enabled: true,
      ready: true,
      scenarios: ["CRM-UX-VAN-01-en", "CRM-UX-VAN-01-fr"]
    }

    config =
      Keyword.update!(config, :features, &(&1 ++ [feature]))
      |> Keyword.update!(:feature_evidence, fn evidence ->
        update_in(
          evidence,
          [:results],
          &Map.merge(&1, %{"CRM-UX-VAN-01-en" => "success", "CRM-UX-VAN-01-fr" => "success"})
        )
      end)

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    assert {:ok, _} = Assistant.set_enabled(scope, true)
    session = %{id: "vancouver-fixture", login: String.duplicate("a", 64)}

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:pauseai_ca, :agent_assistant, value)
        :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
      end

      for {key, value} <- [
            {"PAUSEAI_CA_RELEASE_ID", old_build},
            {"PAUSEAI_CA_GIT_SHA", old_source}
          ] do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    %{scope: scope, session: session, config: config}
  end

  test "Vancouver context fits production turn limits", c do
    config =
      c.config |> Keyword.put(:max_turn_tokens, 16_384) |> Keyword.put(:max_output_tokens, 4096)

    unrelated =
      for n <- 1..14,
          do: %{
            id: "other-#{n}",
            title: "Other feature #{n}",
            summary: "Verified application feature",
            introduced_in: "0.7.0",
            entry_path: "/admin/contacts",
            enabled: true,
            ready: true,
            scenarios: ["CRM-UX-VAN-01-en", "CRM-UX-VAN-01-fr"]
          }

    config = Keyword.update!(config, :features, &(&1 ++ unrelated))
    Application.put_env(:pauseai_ca, :agent_assistant, config)
    assert {:ok, conversation} = Assistant.new_conversation(c.scope)

    assert {:ok, _} =
             Assistant.run(
               c.scope,
               Ecto.UUID.generate(),
               "Show me Vancouver contacts",
               conversation,
               "en",
               guided_mode: true
             )

    assert_received {:guided_provider_called, request}

    assert request["context"]["canadian_references"] ==
             PauseAiCa.Assistant.CanadianReferences.context()
  end

  test "new journey is absent until both exact native outcomes are available", c do
    config =
      Keyword.update!(c.config, :feature_evidence, fn evidence ->
        update_in(evidence, [:results], &Map.put(&1, "CRM-UX-VAN-01-fr", "not_run"))
      end)

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    assert {:error, :guide_unavailable} = GuidedMode.manifest(c.scope, "en")

    # Existing readiness rejects a configured feature with missing evidence.
    # Omitting the new feature preserves the previous guide's complete contract.
    config =
      Keyword.update!(
        config,
        :features,
        &Enum.reject(&1, fn feature -> feature.id == "crm-vancouver-guided" end)
      )

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    assert {:ok, manifest, _} = GuidedMode.manifest(c.scope, "en")
    refute Map.has_key?(manifest["journeys"], VancouverGuide.journey())
    assert Map.has_key?(manifest["journeys"], "crm.audience_preview")
  end

  test "closed plan selects city only and never registers a model-selected write or URL", c do
    {:ok, manifest, _} = GuidedMode.manifest(c.scope, "en")
    plan = VancouverGuide.example_plan(manifest)
    assert {:ok, _} = PhoenixAgentAssistant.GuidedMode.parse(Jason.encode!(plan), manifest)

    bad =
      put_in(plan, ["steps", Access.at(1), "actions", Access.at(1), "arguments", "values"], [
        "V6T"
      ])

    assert {:error, _} = GuidedMode.start(c.scope, Jason.encode!(bad), "en", c.session)
    bad = put_in(plan, ["steps", Access.at(3), "actions", Access.at(0), "type"], "click_button")
    assert {:error, _} = GuidedMode.start(c.scope, Jason.encode!(bad), "en", c.session)

    assert {:error, _} =
             GuidedMode.start(
               c.scope,
               Jason.encode!(Map.put(plan, "url", "https://example.org")),
               "en",
               c.session
             )
  end

  test "human Save and Compose require fresh attributed city list and owned new draft", c do
    state = start(c)
    state = contacts(c, state, [], "")
    state = contacts(c, state, ["Vancouver"], "&cities[]=Vancouver")
    {:ok, pending, command} = GuidedMode.next(c.scope, state, "en", c.session)

    assert command.actions == [
             %{
               type: "activate_menu_item",
               target_id: "manage-menu-navigation-pauseai.contact_lists",
               values: nil
             }
           ]

    {:ok, state, 0} = ack(c, pending, %{"url" => "/manage/lists?locale=en"})
    {:ok, pending, command} = GuidedMode.next(c.scope, state, "en", c.session)

    assert command.human_step &&
             command.actions == [%{type: "focus", target_id: "list_name", values: nil}]

    assert {:waiting, ^pending} = ack(c, pending, %{"url" => "/manage/lists?locale=en"})

    assert {:error, _} =
             GuidedMode.acknowledge(
               c.scope,
               pending,
               obs(c, pending, %{"url" => "/manage/lists?locale=en"}),
               "en",
               %{c.session | id: "other"}
             )

    assert {:error, _} =
             ack(c, %{pending | expires_at: System.monotonic_time(:second) - 1}, %{
               "url" => "/manage/lists?locale=en"
             })

    assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == 0

    {:ok, list} =
      Lists.save(c.scope, nil, %{"name" => "Synthetic Vancouver", "city" => "Vancouver"})

    assert {:ok, state, 0} =
             ack(c, pending, %{
               "url" => "/manage/lists?locale=en",
               "list_id" => list.id,
               "list_revision" => list.revision
             })

    assert {:error, _} =
             ack(c, state, %{
               "url" => "/manage/lists?locale=en",
               "list_id" => list.id,
               "list_revision" => list.revision
             })

    {:ok, pending, command} = GuidedMode.next(c.scope, state, "en", c.session)

    assert command.human_step &&
             command.actions == [
               %{type: "focus", target_id: "contact-list-compose-newsletter", values: nil}
             ]

    assert {:waiting, ^pending} = ack(c, pending, %{"url" => "/manage/lists?locale=en"})
    {:ok, draft} = Drafts.create_for_list(c.scope, list.id)

    assert {:waiting, ^pending, handoff} =
             ack(c, pending, %{"url" => "/manage/lists?locale=en", "draft_id" => draft.id})

    assert handoff.actions == [] && handoff.expected_path == "/manage/mail/drafts/" <> draft.id

    assert {:ok, complete, 0} =
             ack(c, pending, %{
               "url" => "/manage/mail/drafts/#{draft.id}?locale=en",
               "draft_id" => draft.id
             })

    assert complete.index == 5
    assert complete.vancouver.list_id == list.id
    assert complete.vancouver.draft_id == draft.id
  end

  test "existing lists, forged counts, stale criteria, and demotion cannot complete the journey",
       c do
    {:ok, list} =
      Lists.save(c.scope, nil, %{"name" => "Existing Vancouver", "city" => "Vancouver"})

    state = start(c)
    assert {:ok, pending, _} = GuidedMode.next(c.scope, %{state | index: 3}, "en", c.session)

    assert {:error, _} =
             ack(c, pending, %{
               "url" => "/manage/lists?locale=en",
               "list_id" => list.id,
               "list_revision" => list.revision,
               "count" => 999
             })

    {:ok, changed} =
      Lists.save(c.scope, list, %{"name" => list.name, "city" => "Vancouver", "fsas" => "V6T"})

    assert {:error, _} =
             ack(c, pending, %{
               "url" => "/manage/lists?locale=en",
               "list_id" => changed.id,
               "list_revision" => changed.revision
             })

    c.scope.user |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    assert {:error, _} = GuidedMode.next(c.scope, state, "en", c.session)
  end

  defp start(c) do
    {:ok, manifest, _} = GuidedMode.manifest(c.scope, "en")

    {:ok, state} =
      GuidedMode.start(
        c.scope,
        Jason.encode!(VancouverGuide.example_plan(manifest)),
        "en",
        c.session
      )

    state
  end

  defp contacts(c, state, cities, query) do
    {:ok, pending, _} = GuidedMode.next(c.scope, state, "en", c.session)
    filters = CRM.Geography.filters(%{"cities" => cities})

    {:ok, state, count} =
      ack(c, pending, %{
        "url" => "/admin/contacts?locale=en" <> query,
        "filters" => filters,
        "count" => 999
      })

    assert count == 0
    state
  end

  defp obs(c, state, data),
    do: Map.merge(data, %{"token" => state.token, "session" => c.session.login})

  defp ack(c, state, data),
    do: GuidedMode.acknowledge(c.scope, state, obs(c, state, data), "en", c.session)
end
