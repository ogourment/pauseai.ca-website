defmodule PauseAiCa.Assistant.FeatureCatalogue do
  @moduledoc """
  Curated coaching metadata bound to the deployed acceptance artifact.

  The caller supplies trusted release identity, including `:source_sha` (which
  the health payload alone does not contain). Evidence v1 records the source,
  version and pipeline; the deployment workflow constructs the release ID from
  that version and pipeline. Unbound local reports are never accepted.
  Only scenario IDs and their recorded statuses leave this loader.

  `introduced_in` uses the source version at addition of the corresponding native
  scenario file, not a claim about its first deployment. The consumer currently
  supplies no `last_seen_version`, so these anchors do not announce old features
  as new. Runtime permissions remain independent of this catalogue.
  """

  @max_bytes 2 * 1024 * 1024
  @statuses ~w(success failure running ignored not_run)
  @specs [
    {"crm-guided", "Guided contact geography",
     "Preview a configured area through reviewed UI steps.", "/admin/contacts",
     ["CRM-ASSIST-GUIDE-01"], nil, "0.6.14"},
    {"crm-geography", "Contact geography", "Filter contacts by recorded geography.",
     "/admin/contacts", ["GEO-PAI-01"], nil, "0.5.37"},
    {"newsletter-compose", "Newsletter composition", "Compose and review a language edition.",
     "/manage/mail", ["PA-NEWS-01", "MAIL-GEO-01"], nil, "0.5.62"},
    {"newsletter-lists", "Dynamic mailing lists", "Prepare a whole-list recipient snapshot.",
     "/manage/mail/newsletters", ["LIST-NEWS-01"], nil, "0.5.13"},
    {"newsletter-results", "Newsletter results", "Compare cached send results and saved content.",
     "/manage/mail/results", ["PA-NEWS-RESULTS-01"], nil, "0.5.50"},
    {"group-admission", "Group admission", "Review account-linked local group admission.",
     "/manage/groups", ["JOIN-PAI-01"], :incubators_enabled, "0.5.37"},
    {"organizer-tasks", "Organizer tasks", "Manage scoped tasks and their activity.",
     "/manage/tasks", ["TASK-PAI-01", "TASK-PAI-01-authority"], :tasks_enabled, "0.5.36"},
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
         features: features(),
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
      {:ok,
       %{
         "schema_version" => "acceptance_harness.evidence.v1",
         "app" => Map.take(report["app"], ~w(version commit pipeline_id)),
         "scenarios" =>
           results
           |> Enum.sort()
           |> Enum.map(fn {id, status} -> %{"id" => id, "status" => status} end)
       }}
    else
      _ -> {:error, :unverified}
    end
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

  defp features do
    Enum.map(@specs, fn {id, title, summary, path, scenarios, flag, version} ->
      %{
        id: id,
        title: title,
        summary: summary,
        introduced_in: version,
        entry_path: path,
        controls: if(id == "crm-guided", do: ["menu.contacts", "crm.geography.areas"], else: []),
        scenarios: for(prefix <- scenarios, locale <- ["en", "fr"], do: "#{prefix}-#{locale}"),
        enabled: is_nil(flag) or Application.get_env(:pauseai_ca, flag, false) == true,
        ready: true
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
