defmodule PauseAiCa.Assistant.CatalogueVisibilityTest do
  use PauseAiCa.DataCase, async: true

  import PauseAiCa.AccountsFixtures

  alias PauseAiCa.{Assistant, Repo, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Assistant.FeatureCatalogue

  @import_id "historical-email-import"
  @responsibilities_id "group-responsibilities"
  @tasks_id "organizer-tasks"
  @ids [@import_id, @responsibilities_id, @tasks_id]

  @tag :tmp_dir
  test "review refresh projects verified coaching and rechecks current group authority", %{
    tmp_dir: dir
  } do
    admin =
      user_fixture()
      |> Ecto.Changeset.change(superadmin: true)
      |> Repo.update!()
      |> Scope.for_user()

    manager = user_fixture()
    manager_scope = Scope.for_user(manager)
    unrelated = user_scope_fixture()
    {:ok, group} = Volunteers.create_group(admin, %{name: "Review organizer group"})
    {:ok, grant} = Volunteers.assign_manager(admin, group.id, manager.email)

    summaries = %{
      "HIST-EMAIL-01" => "Review the imported message.",
      "TASK-MEMBER-01" => "Save the ongoing responsibility.",
      "TASK-PAI-01" => "Save the completed task."
    }

    config = projected_config(dir, summaries)

    assert coaching(admin, config) == %{
             @import_id => {"available", summaries["HIST-EMAIL-01"]},
             @responsibilities_id => {"available", summaries["TASK-MEMBER-01"]},
             @tasks_id => {"available", summaries["TASK-PAI-01"]}
           }

    assert coaching(manager_scope, config) == %{
             @responsibilities_id => {"available", summaries["TASK-MEMBER-01"]},
             @tasks_id => {"available", summaries["TASK-PAI-01"]}
           }

    without_summary = projected_config(dir, Map.delete(summaries, "TASK-MEMBER-01"))
    without_journey = projected_config(dir, summaries, "TASK-MEMBER-01-fr")

    for incomplete <- [without_summary, without_journey] do
      assert coaching(manager_scope, incomplete)[@responsibilities_id] ==
               {"disabled", "Ongoing group responsibilities"}
    end

    assert coaching(unrelated, config) == %{}
    assert :ok = Volunteers.revoke_manager(admin, grant.id)
    assert coaching(manager_scope, config) == %{}
  end

  defp coaching(scope, config) do
    saved = %{"context" => %{"locale" => "en", "features" => [%{"id" => "stale"}]}}
    assert {:ok, refreshed} = Assistant.refresh_reviewed_context(scope, saved, config)

    for feature <- get_in(refreshed, ["context", "features"]),
        feature["id"] in @ids,
        into: %{},
        do: {feature["id"], {feature["status"], feature["summary"]}}
  end

  defp projected_config(dir, summaries, missing_scenario \\ nil) do
    health = AcceptanceHarness.Health.payload()

    identity = %{
      version: health.version,
      pipeline_id: "42",
      source_sha: String.duplicate("a", 40),
      release_id: "pauseai-ca-#{health.version}-42"
    }

    scenarios =
      for key <- ~w(HIST-EMAIL-01 TASK-MEMBER-01 TASK-PAI-01 TASK-PAI-01-authority),
          locale <- ~w(en fr),
          id = "#{key}-#{locale}",
          id != missing_scenario,
          do: %{"id" => id, "status" => "success"}

    path = Path.join(dir, "coaching.json")

    File.write!(
      path,
      Jason.encode!(%{
        "schema_version" => "acceptance_harness.evidence.v1",
        "app" => %{
          "version" => identity.version,
          "commit" => identity.source_sha,
          "pipeline_id" => identity.pipeline_id
        },
        "scenarios" => scenarios,
        "assistant_summaries" => summaries
      })
    )

    assert {:ok, loaded} = FeatureCatalogue.load(identity, evidence_path: path)

    [
      features: loaded.features,
      feature_evidence: %{loaded.feature_evidence | build: health.release_id}
    ]
  end
end
