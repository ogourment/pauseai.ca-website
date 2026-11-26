defmodule PauseAiCa.Assistant.FeatureCatalogue do
  @moduledoc """
  Curated coaching metadata bound to the deployed acceptance artifact.

  The caller supplies trusted release identity, including `:source_sha` (which
  the health payload alone does not contain). Evidence v1 records the source,
  version and pipeline; the deployment workflow constructs the release ID from
  that version and pipeline. Unbound local reports are never accepted.
  For selected workflows, a successful bilingual browser journey also supplies its authored coaching text.

  `introduced_in` uses the source version at addition of the corresponding native
  scenario file, not a claim about its first deployment. The consumer currently
  supplies no `last_seen_version`, so these anchors do not announce old features
  as new. Runtime permissions remain independent of this catalogue.
  """

  @max_bytes 2 * 1024 * 1024
  @statuses ~w(success failure running ignored not_run)
  @specs [
    {"mp-guided", "Guided letter to your MP",
     "Find your MP, review your own letter and record your action through the website.",
     "/en/contact-your-mp?guide=1", ["CRM-ASSIST-GUIDE-02"], :mp_guide_enabled, "0.6.17"},
    {"mp-templates", "Shared MP letter templates",
     "Publish a reviewed bilingual template so each person can adapt and send their own letter.",
     "/manage/mp-templates", ["CRM-ASSIST-GUIDE-03-CMS", "CRM-ASSIST-GUIDE-03"], nil, "0.6.17"},
    {"crm-guided", "Guided contact geography",
     "Preview a configured area through reviewed UI steps.", "/admin/contacts",
     ["CRM-ASSIST-GUIDE-01"], nil, "0.6.17"},
    {"crm-geography", "Contact geography", "Filter contacts by recorded geography.",
     "/admin/contacts", ["GEO-PAI-01"], nil, "0.5.37"},
    {"historical-email-import", "Import an existing email", {:journey, "HIST-EMAIL-01"},
     "/manage/mail/import", ["HIST-EMAIL-01"], nil, "0.8.49"},
    {"newsletter-compose", "Newsletter composition", "Compose and review a language edition.",
     "/manage/mail", ["PA-NEWS-01", "MAIL-GEO-01"], nil, "0.5.62"},
    {"newsletter-lists", "Dynamic mailing lists", "Prepare a whole-list recipient snapshot.",
     "/manage/mail/newsletters", ["LIST-NEWS-01"], nil, "0.5.13"},
    {"newsletter-results", "Newsletter results", "Compare cached send results and saved content.",
     "/manage/mail/results", ["PA-NEWS-RESULTS-01"], nil, "0.5.50"},
    {"group-admission", "Group admission", "Review account-linked local group admission.",
     "/manage/groups", ["JOIN-PAI-01"], :incubators_enabled, "0.5.37"},
    {"group-enrollment", "Existing group accounts",
     "Superadmins add confirmed accounts as group members or managers, with organizer attribution.",
     "/manage/groups", ["GROUP-ADMIN-01"], :incubators_enabled, "0.6.19"},
    {"group-public-events", "Public groups and events",
     "Configure a local group or incubator and its next public event, then review the public directory.",
     "/manage/groups", ["PUBLIC-GROUPS-EVENTS-01", "GROUP-EVENT-EDITOR-01"], :incubators_enabled,
     "0.7.0"},
    {"local-followup", "Local-interest follow-up",
     "Joiners open Get involved → Local groups, select their group, send their interests, and confirm by email. Organizers use Manage → Local participation to claim follow-up, contact the volunteer, or check onboarding calls.",
     "/manage/local-interest", ["LOCAL-FOLLOWUP-01", "GROUP-PART-01"], nil, "0.7.0"},
    {"group-responsibilities", "Ongoing group responsibilities", {:journey, "TASK-MEMBER-01"},
     "/manage/groups?tab=responsibilities", ["TASK-MEMBER-01"], :incubators_enabled, "0.8.26"},
    {"task-member-assignment", "Group member task assignment",
     "In Manage → Tasks choose a group, Add task, Assigned to, then Save. Approved members read their assignment under My account → Volunteer profile → My group work.",
     "/manage/tasks", ["TASK-MEMBER-01"], :tasks_enabled, "0.7.0"},
    {"account-profiles", "My profile and Volunteer profile",
     "Open My account → My profile to save contact details and an optional postal area. Find my MP is a separate full-code lookup. Open Volunteer profile for group work, availability, skills and sharing preferences.",
     "/en/profile", ["PROFILE-UX-01"], nil, "0.8.39"},
    {"organizer-tasks", "Organizer tasks", {:journey, "TASK-PAI-01"}, "/manage/tasks",
     ["TASK-PAI-01", "TASK-PAI-01-authority"], :tasks_enabled, "0.5.36"},
    {"blog-editor", "Blog editing", "Edit Markdown posts and review reader sections.",
     "/manage/blog", ["BLOG-01"], nil, "0.5.51"},
    {"newsletter-rich-paste", "Rich newsletter paste", "Save editable rich clipboard content.",
     "/manage/mail", ["PA-NEWS-PASTE-01"], nil, "0.5.14"}
  ]

  def load(identity, opts \\ []) do
    with true <- valid_identity?(identity),
         {:ok, bytes} <- read_bounded(Keyword.get_lazy(opts, :evidence_path, &default_path/0)),
         {:ok, report} <- Jason.decode(bytes),
         true <- bound?(report, identity),
         {:ok, results} <- results(report) do
      {:ok,
       %{
         features: features(Map.get(report, "assistant_summaries", %{}), results),
         feature_evidence: %{build: identity.release_id, results: results}
       }}
    else
      _ -> {:error, :unverified}
    end
  rescue
    _ -> {:error, :unverified}
  end

  @doc false
  def project(report, identity) do
    with true <- valid_identity?(identity) and bound?(report, identity),
         {:ok, results} <- results(report) do
      projection =
        %{
          "schema_version" => "acceptance_harness.evidence.v1",
          "app" => Map.take(report["app"], ~w(version commit pipeline_id)),
          "scenarios" =>
            results
            |> Enum.sort()
            |> Enum.map(fn {id, status} -> %{"id" => id, "status" => status} end)
        }

      summaries = project_summaries(report["scenarios"])

      {:ok,
       if(summaries == %{},
         do: projection,
         else: Map.put(projection, "assistant_summaries", summaries)
       )}
    else
      _ -> {:error, :unverified}
    end
  end

  # The capture contains private HTML and fixture data. Read only the explicit
  # procedural text on one successful step of each registered language journey.
  defp project_summaries(scenarios) do
    by_id = Map.new(scenarios, &{&1["id"], &1})

    for {_, _, {:journey, id}, _, _, _, _} <- @specs,
        english = recorded_summary(by_id["#{id}-en"]),
        is_binary(english),
        recorded_summary(by_id["#{id}-fr"]) == english,
        into: %{},
        do: {id, english}
  end

  defp recorded_summary(%{"status" => "success", "steps" => steps}) when is_list(steps) do
    case for(
           %{"status" => "success", "metadata" => %{"assistant_summary" => text}} <- steps,
           do: text
         ) do
      [summary] when is_binary(summary) and byte_size(summary) in 1..1024 -> summary
      _ -> nil
    end
  end

  defp recorded_summary(_), do: nil

  @doc "Release gate for every feature whose guidance comes from a browser journey."
  def require_workflow_evidence(%{features: features, feature_evidence: %{results: results}}) do
    required = for {id, _, {:journey, _}, _, _, _, _} <- @specs, do: id

    if Enum.all?(required, fn id ->
         Enum.any?(features, fn feature ->
           feature.id == id and feature.ready and
             Enum.all?(feature.scenarios, &(results[&1] == "success"))
         end)
       end),
       do: :ok,
       else: {:error, :missing_workflow_evidence}
  end

  @doc "Build-time projection from a trusted CI report; no report bodies enter runtime coaching."
  def package_projection(source, destination, identity) do
    with {:ok, bytes} <- read_bounded(source, 64 * 1024 * 1024),
         {:ok, report} <- Jason.decode(bytes),
         {:ok, projection} <- project(report, identity),
         {:ok, encoded} <- Jason.encode(projection),
         true <- byte_size(encoded) <= @max_bytes,
         :ok <- File.write(destination, encoded) do
      :ok
    else
      _ -> {:error, :unverified}
    end
  rescue
    _ -> {:error, :unverified}
  end

  defp valid_identity?(%{
         version: version,
         pipeline_id: pipeline,
         release_id: release,
         source_sha: sha
       })
       when is_binary(version) and is_binary(pipeline) and is_binary(release) and is_binary(sha) do
    match?({:ok, _}, Version.parse(version)) and Regex.match?(~r/\A[1-9][0-9]{0,24}\z/, pipeline) and
      Regex.match?(~r/\A[0-9a-f]{40}\z/, sha) and
      release == "pauseai-ca-#{version}-#{pipeline}"
  end

  defp valid_identity?(_), do: false

  defp bound?(%{"schema_version" => "acceptance_harness.evidence.v1", "app" => app}, identity)
       when is_map(app) do
    app["version"] == identity.version and app["commit"] == identity.source_sha and
      app["pipeline_id"] == identity.pipeline_id
  end

  defp bound?(_, _), do: false

  defp results(%{"scenarios" => scenarios})
       when is_list(scenarios) and length(scenarios) <= 2000 do
    Enum.reduce_while(scenarios, {:ok, %{}}, fn
      %{"id" => id, "status" => status}, {:ok, acc}
      when is_binary(id) and byte_size(id) in 1..160 and status in @statuses ->
        if Map.has_key?(acc, id),
          do: {:halt, {:error, :unverified}},
          else: {:cont, {:ok, Map.put(acc, id, status)}}

      _, _ ->
        {:halt, {:error, :unverified}}
    end)
  end

  defp results(_), do: {:error, :unverified}

  defp features(summaries, results) do
    Enum.map(@specs, fn {id, title, summary, path, scenarios, flag, version} ->
      guidance =
        case summary do
          {:journey, key} ->
            with true <- is_map(summaries),
                 true <- Enum.all?(["en", "fr"], &(results["#{key}-#{&1}"] == "success")),
                 text when is_binary(text) and byte_size(text) in 1..1024 <- summaries[key] do
              text
            else
              _ -> nil
            end

          text ->
            text
        end

      %{
        id: id,
        title: title,
        summary: guidance || title,
        introduced_in: version,
        entry_path: path,
        controls: if(id == "crm-guided", do: ["menu.contacts", "crm.geography.areas"], else: []),
        scenarios: for(prefix <- scenarios, locale <- ["en", "fr"], do: "#{prefix}-#{locale}"),
        enabled: is_nil(flag) or Application.get_env(:pauseai_ca, flag, false) == true,
        ready: is_binary(guidance)
      }
    end)
  end

  defp default_path,
    do: Application.app_dir(:pauseai_ca, "priv/acceptance_evidence/assistant-features.json")

  defp read_bounded(path, maximum \\ @max_bytes)

  defp read_bounded(path, maximum) when is_binary(path) do
    with {:ok, %{type: :regular, size: size}} when size <= maximum <- File.lstat(path),
         {:ok, file} <- File.open(path, [:read, :binary]) do
      try do
        case IO.binread(file, maximum + 1) do
          bytes when is_binary(bytes) and byte_size(bytes) <= maximum -> {:ok, bytes}
          _ -> {:error, :unverified}
        end
      after
        File.close(file)
      end
    else
      _ -> {:error, :unverified}
    end
  end

  defp read_bounded(_, _), do: {:error, :unverified}
end
