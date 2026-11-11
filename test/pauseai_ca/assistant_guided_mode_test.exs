defmodule PauseAiCa.AssistantGuidedModeTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Assistant, GuidedModeFixtures, Repo}
  alias PauseAiCa.Assistant.GuidedMode, as: Guide
  alias PhoenixAgentAssistant.Store

  setup do
    previous = Application.fetch_env(:pauseai_ca, :agent_assistant)
    old_build = System.get_env("PAUSEAI_CA_RELEASE_ID")
    old_source = System.get_env("PAUSEAI_CA_GIT_SHA")
    System.put_env("PAUSEAI_CA_RELEASE_ID", "guided-synthetic-fixture")
    System.put_env("PAUSEAI_CA_GIT_SHA", String.duplicate("a", 40))
    Application.put_env(:pauseai_ca, :agent_assistant, GuidedModeFixtures.configuration(self()))
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    assert {:ok, _} = Assistant.set_enabled(scope, true)

    on_exit(fn ->
      case previous do
        {:ok, v} -> Application.put_env(:pauseai_ca, :agent_assistant, v)
        :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
      end

      for {key, value} <- [
            {"PAUSEAI_CA_RELEASE_ID", old_build},
            {"PAUSEAI_CA_GIT_SHA", old_source}
          ] do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    %{scope: scope, admin: admin}
  end

  defp start(c, locale \\ "en") do
    {:ok, manifest, _} = Guide.manifest(c.scope, locale)
    json = Guide.example_plan(manifest, "toronto_gta") |> Jason.encode!()

    assert {:ok, state} =
             Guide.start(c.scope, json, locale, %{
               id: "synthetic-session",
               login: String.duplicate("a", 64)
             })

    state
  end

  test "released JSON is available only after actual fixture input/output reviews", c do
    assert {:ok, conversation} = Assistant.new_conversation(c.scope)

    assert {:ok, reply} =
             Assistant.run(
               c.scope,
               Ecto.UUID.generate(),
               "Show the configured area",
               conversation,
               "en",
               guided_mode: true
             )

    assert_received {:guided_provider_called, request}
    assert request["context"]["guided_mode"]["manifest_json"]

    assert request["context"]["canadian_references"] ==
             PauseAiCa.Assistant.CanadianReferences.context()

    assert byte_size(PhoenixAgentAssistant.Canonical.encode(request)) <= 40_000

    assert {:ok, _} =
             Guide.start(c.scope, reply.text, "en", %{
               id: "synthetic-session",
               login: String.duplicate("a", 64)
             })

    assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == 0
  end

  test "steps bind actual observation route values session and current actor rights", c do
    state = start(c)

    assert {:ok, pending, command} =
             Guide.next(c.scope, state, "en", %{
               id: "synthetic-session",
               login: String.duplicate("a", 64)
             })

    assert command.actions == [
             %{
               type: "activate_menu_item",
               target_id: "manage-menu-navigation-pauseai.contacts",
               values: nil
             }
           ]

    filters = PauseAiCa.CRM.Geography.filters(%{})

    observation = %{
      "token" => pending.token,
      "session" => String.duplicate("a", 64),
      "url" => "http://127.0.0.1/admin/contacts?locale=en",
      "filters" => filters,
      "q" => "",
      "region" => "",
      "count" => 0
    }

    assert {:error, _} = Guide.acknowledge(c.scope, pending, observation, "en", "another-session")

    assert {:error, _} =
             Guide.acknowledge(
               c.scope,
               pending,
               %{observation | "url" => "/manage/mail?locale=en"},
               "en",
               %{id: "synthetic-session", login: String.duplicate("a", 64)}
             )

    assert {:error, _} =
             Guide.acknowledge(
               c.scope,
               pending,
               %{observation | "session" => String.duplicate("b", 64)},
               "en",
               %{id: "synthetic-session", login: String.duplicate("a", 64)}
             )

    assert {:ok, advanced, 0} =
             Guide.acknowledge(c.scope, pending, observation, "en", %{
               id: "synthetic-session",
               login: String.duplicate("a", 64)
             })

    assert advanced.index == 1
    Repo.update!(Ecto.Changeset.change(c.admin, superadmin: false))

    assert {:error, _} =
             Guide.next(c.scope, advanced, "en", %{
               id: "synthetic-session",
               login: String.duplicate("a", 64)
             })

    refute Store.enabled?(Store.new(Repo, "different-namespace"))
  end

  test "stale build wrong area raw selectors and failed evidence deny without a guide", c do
    state = start(c)
    System.put_env("PAUSEAI_CA_GIT_SHA", String.duplicate("b", 40))

    assert {:error, _} =
             Guide.next(c.scope, state, "en", %{
               id: "synthetic-session",
               login: String.duplicate("a", 64)
             })

    config =
      Assistant.configuration() |> Keyword.put(:feature_evidence, %{build: "stale", results: %{}})

    Application.put_env(:pauseai_ca, :agent_assistant, config)
    assert {:error, _} = Guide.manifest(c.scope, "en")
  end
end
