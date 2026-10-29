defmodule PauseAiCa.GithubDeliveryContractTest do
  use ExUnit.Case, async: true

  @workflows Path.expand("../../.github/workflows", __DIR__)
  @harness "ogourment/github-ci-cd-harness/.github/workflows/"
  @ci_ref "v0.4.45"
  @delivery_ref "v0.4.54"

  test "normal CI builds the release and stages it without production credentials" do
    ci = File.read!(Path.join(@workflows, "ci.yml"))

    assert ci =~ "uses: ./.github/workflows/phoenix-crm.yml"
    assert ci =~ "#{@harness}phoenix-delivery.yml@#{@delivery_ref}"
    assert ci =~ "build-release: true"
    assert ci =~ "run-acceptance: true"
    assert ci =~ "deploy-staging: true"
    assert ci =~ "deploy-production: false"
    assert ci =~ "needs: [repository-boundary, phoenix]"
    refute ci =~ "secrets.PRODUCTION_"
  end

  test "public package CI retains the reviewed quality gates without private dependency credentials" do
    adapter = File.read!(Path.join(@workflows, "phoenix-crm.yml"))
    ci = File.read!(Path.join(@workflows, "ci.yml"))

    assert adapter =~ "Consumer-local adapter based on ogourment/github-ci-cd-harness #{@ci_ref}"

    for gate <- [
          "mix format --check-formatted",
          "mix compile --warnings-as-errors",
          "run: ${{ inputs.test-command }}",
          "run: mix test.atdd",
          "run: mix assets.deploy",
          "run: mix release --overwrite",
          "Package verified acceptance evidence with the exact release",
          "Archive production release with Unix permissions",
          "Upload production release"
        ] do
      assert adapter =~ gate
    end

    refute adapter =~ "secrets."
    refute adapter =~ "ACCEPTANCE_HARNESS_PATH"
    refute adapter =~ "deploy-production: true"

    for secret <- ~w(MAIL_PACKAGE_DEPLOY_KEY CMS_PACKAGE_DEPLOY_KEY CRM_PACKAGE_DEPLOY_KEY
                     EDITOR_PACKAGE_DEPLOY_KEY TASKS_PACKAGE_DEPLOY_KEY COMMUNITY_PACKAGE_DEPLOY_KEY
                     SHELL_PACKAGE_DEPLOY_KEY ACCEPTANCE_HARNESS_GITHUB_DEPLOY_KEY) do
      refute ci =~ "secrets.#{secret}"
    end

    {lock, _} = Code.eval_file(Path.expand("../../mix.lock", __DIR__))

    for package <- ~w(phoenix_app_shell phoenix_cms phoenix_crm phoenix_community phoenix_tasks
                      phoenix_mail_workflow phoenix_markdown_editor acceptance_harness)a do
      assert {:git, url, sha, options} = Map.fetch!(lock, package)
      assert url == "https://github.com/ogourment/#{package}-compiled.git"
      assert sha =~ ~r/\A[0-9a-f]{40}\z/
      assert options[:ref] == sha
    end
  end

  test "manual production selects an explicit CI run through the shared promoter" do
    promotion = File.read!(Path.join(@workflows, "promote-production.yml"))

    assert promotion =~ "workflow_dispatch:"
    assert promotion =~ ~r/source-run-id:.*?required: true/s
    assert promotion =~ "#{@harness}phoenix-promote-production.yml@#{@delivery_ref}"
    assert promotion =~ "source-run-id: ${{ inputs.source-run-id }}"
    assert promotion =~ "source-workflow: .github/workflows/ci.yml"
    assert promotion =~ "artifact-name: pauseai-ca-release"
    assert promotion =~ "otp-app: pauseai_ca"
    assert promotion =~ "actions: read"
    assert promotion =~ "contents: write"
    refute promotion =~ "phoenix.yml@"
    refute promotion =~ "phoenix-delivery.yml@"
    refute promotion =~ "secrets.STAGING_"
  end
end
