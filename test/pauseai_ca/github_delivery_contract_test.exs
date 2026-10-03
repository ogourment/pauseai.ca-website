defmodule PauseAiCa.GithubDeliveryContractTest do
  use ExUnit.Case, async: true

  @workflows Path.expand("../../.github/workflows", __DIR__)
  @harness "ogourment/github-ci-cd-harness/.github/workflows/"
  @ci_ref "v0.4.45"
  @delivery_ref "v0.4.41"

  test "normal CI builds the release and stages it without production credentials" do
    ci = File.read!(Path.join(@workflows, "ci.yml"))

    assert ci =~ "uses: ./.github/workflows/phoenix-crm.yml"
    assert ci =~ "#{@harness}phoenix-delivery.yml@#{@delivery_ref}"
    assert ci =~ "acceptance-harness-github-ref: v0.10.6"
    assert ci =~ "acceptance-harness-github-sha: fb318c868be948316fcb1ebbd144d1a075f6d8fd"
    assert ci =~ "secrets.ACCEPTANCE_HARNESS_GITHUB_DEPLOY_KEY"
    assert ci =~ "build-release: true"
    assert ci =~ "run-acceptance: true"
    assert ci =~ "deploy-staging: true"
    assert ci =~ "deploy-production: false"
    assert ci =~ "needs: [repository-boundary, phoenix]"
    refute ci =~ "secrets.PRODUCTION_"
  end

  test "the private package adapter retains the reviewed Phoenix quality and release gates" do
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

    assert adapter =~ "StrictHostKeyChecking yes"
    assert adapter =~ "IdentitiesOnly yes"
    assert adapter =~ "IdentityFile $HOME/.ssh/phoenix_crm_ci"
    assert adapter =~ "IdentityFile $HOME/.ssh/phoenix_editor_ci"
    refute adapter =~ "secrets.PRODUCTION_"
    refute adapter =~ "deploy-production: true"

    for secret <- ~w(CRM_PACKAGE_DEPLOY_KEY EDITOR_PACKAGE_DEPLOY_KEY FORGEJO_PACKAGE_KNOWN_HOSTS) do
      assert ci =~ "secrets.#{secret}"
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
