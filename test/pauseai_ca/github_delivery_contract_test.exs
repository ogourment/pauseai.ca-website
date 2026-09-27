defmodule PauseAiCa.GithubDeliveryContractTest do
  use ExUnit.Case, async: true

  @workflows Path.expand("../../.github/workflows", __DIR__)
  @harness "ogourment/github-ci-cd-harness/.github/workflows/"
  @ci_ref "v0.4.45"
  @delivery_ref "v0.4.41"

  test "normal CI builds the release and stages it without production credentials" do
    ci = File.read!(Path.join(@workflows, "ci.yml"))

    assert ci =~ "#{@harness}phoenix.yml@#{@ci_ref}"
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
