defmodule PauseAiCaWeb.AssistantInstructionsLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Assistant, Repo}
  alias PauseAiCa.Assistant.{InstructionRevision, Instructions}

  setup do
    previous = Application.get_env(:pauseai_ca, :assistant_instruction_editors)
    previous_build = System.get_env("PAUSEAI_CA_RELEASE_ID")
    System.put_env("PAUSEAI_CA_RELEASE_ID", "assistant-synthetic-fixture")
    config = Application.get_env(:pauseai_ca, :agent_assistant)

    Application.put_env(
      :pauseai_ca,
      :agent_assistant,
      PauseAiCa.AssistantFixtures.configuration()
    )

    owner = user_fixture(%{email: "instruction-owner@example.org"}) |> grant_superadmin()
    outsider = user_fixture(%{email: "instruction-other@example.org"}) |> grant_superadmin()
    member = user_fixture(%{email: "instruction-member@example.org"})

    Application.put_env(:pauseai_ca, :assistant_instruction_editors, [
      owner.email,
      member.email,
      "private-list-entry@example.org"
    ])

    on_exit(fn ->
      restore(:assistant_instruction_editors, previous)
      restore(:agent_assistant, config)

      if previous_build,
        do: System.put_env("PAUSEAI_CA_RELEASE_ID", previous_build),
        else: System.delete_env("PAUSEAI_CA_RELEASE_ID")
    end)

    %{owner: owner, outsider: outsider, member: member, scope: Accounts.Scope.for_user(owner)}
  end

  test "only allowlisted current confirmed superadmins see the link or editor", c do
    private_conn =
      c.conn |> log_in_user(c.owner) |> get("/admin/assistant/instructions?locale=en")

    assert response(private_conn, 200) =~ "assistant-instructions"
    assert get_resp_header(private_conn, "cache-control") == ["private, no-store"]
    {:ok, _, html} = live(log_in_user(c.conn, c.owner), "/admin/assistant?locale=en")
    assert html =~ "assistant-instructions-link"
    {:ok, _, html} = live(log_in_user(c.conn, c.outsider), "/admin/assistant?locale=en")
    refute html =~ "assistant-instructions-link"
    refute html =~ "private-list-entry@example.org"

    for user <- [c.outsider, c.member] do
      conn = c.conn |> log_in_user(user) |> get("/admin/assistant/instructions?locale=en")
      assert response(conn, 404) == "Not found"
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
      refute Instructions.permitted?(Accounts.Scope.for_user(user))
      assert {:error, :unauthorized} = Instructions.get(Accounts.Scope.for_user(user))
      assert {:error, :unauthorized} = Instructions.history(Accounts.Scope.for_user(user))

      assert {:error, :unauthorized} =
               Instructions.save(Accounts.Scope.for_user(user), 0, "forged")

      assert {:error, :unauthorized} = Instructions.publish(Accounts.Scope.for_user(user), 0)
    end
  end

  test "draft saves survive reload and only explicit publish changes actual provider instructions",
       c do
    {:ok, fallback} = Instructions.effective()

    {:ok, view, html} =
      live(log_in_user(c.conn, c.owner), "/admin/assistant/instructions?locale=en")

    assert html =~ "Using the bundled application instructions"
    refute html =~ "private-list-entry@example.org"
    assert has_element?(view, "#assistant-instruction-form fieldset:not([disabled])")

    view
    |> form("#assistant-instruction-form",
      instructions: %{source: "Coach organizers with concrete local actions."}
    )
    |> render_submit()

    assert has_element?(view, "#assistant-instruction-status", "Draft saved")
    assert {:ok, ^fallback} = Instructions.effective()
    assert {:ok, draft} = Instructions.get(c.scope)
    assert draft.revision == 1
    assert draft.source == "Coach organizers with concrete local actions."

    {:ok, view, _} = live(log_in_user(c.conn, c.owner), "/admin/assistant/instructions?locale=en")
    view |> element("#assistant-instruction-publish") |> render_click()
    assert has_element?(view, "#assistant-instruction-status", "Instructions published")
    assert {:ok, effective} = Instructions.effective()
    assert effective.source == draft.source
    assert effective.revision == 2
    assert {_module, options} = Assistant.configuration()[:provider]
    assert options[:instructions] == draft.source
    assert {:ok, history} = Instructions.history(c.scope)
    assert Enum.map(history, & &1.action) == ["publish", "save"]
    assert Enum.all?(history, &(&1.editor_id == c.owner.id))
    assert Enum.map(history, & &1.revision) == [2, 1]
  end

  test "draft changes keep the published version and publishing invalidates admitted turns", c do
    assert {:ok, _} = Assistant.set_enabled(c.scope, true)
    config = Assistant.configuration()
    assert :ok = Assistant.authorize(c.scope, :provider, config)
    assert {:ok, draft} = Instructions.save(c.scope, 0, "First coaching version")
    assert Assistant.configuration()[:instruction_binding] == config[:instruction_binding]
    assert :ok = Assistant.authorize(c.scope, :provider, config)
    assert {:ok, published} = Instructions.publish(c.scope, draft.revision)
    refute Assistant.configuration()[:instruction_binding] == config[:instruction_binding]
    # Permission and configuration validation happen before provider I/O.
    assert {:error, :forbidden} = Assistant.authorize(c.scope, :provider, config)
    assert {:ok, _} = Instructions.save(c.scope, published.revision, "Another draft")
    assert {:ok, %{source: "First coaching version"}} = Instructions.effective()
  end

  test "fresh account email and role protect stale scopes and forged events", c do
    {:ok, view, _} = live(log_in_user(c.conn, c.owner), "/admin/assistant/instructions?locale=en")
    c.owner |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()
    refute Instructions.permitted?(c.scope)
    render_click(view, "save", %{"instructions" => %{"source" => "forged after revocation"}})
    assert_redirect(view, "/")
    assert Repo.aggregate(InstructionRevision, :count) == 0
    assert {:error, :unauthorized} = Instructions.publish(c.scope, 0)
  end

  test "allowlist removal and changed account email immediately deny existing scopes", c do
    Application.put_env(:pauseai_ca, :assistant_instruction_editors, [])
    refute Instructions.permitted?(c.scope)
    Application.put_env(:pauseai_ca, :assistant_instruction_editors, [c.owner.email])
    c.owner |> Ecto.Changeset.change(email: "changed-owner@example.org") |> Repo.update!()
    refute Instructions.permitted?(c.scope)
    assert {:error, :unauthorized} = Instructions.get(c.scope)
  end

  test "unsaved edits and concurrent stale revisions cannot publish or overwrite", c do
    {:ok, view, _} = live(log_in_user(c.conn, c.owner), "/admin/assistant/instructions?locale=en")

    view
    |> form("#assistant-instruction-form", instructions: %{source: "Unsaved"})
    |> render_change()

    assert has_element?(view, "#assistant-instruction-publish[disabled]")
    render_click(view, "publish")
    assert Repo.aggregate(InstructionRevision, :count) == 0

    assert {:ok, saved} = Instructions.save(c.scope, 0, "Saved elsewhere")
    assert {:error, :stale} = Instructions.save(c.scope, 0, "Stale overwrite")
    assert {:error, :stale} = Instructions.publish(c.scope, 0)
    assert {:ok, %{source: "Saved elsewhere"}} = Instructions.get(c.scope)
    assert saved.revision == 1
  end

  test "empty or oversized drafts preserve the current instructions", c do
    {:ok, fallback} = Instructions.effective()
    assert {:error, %Ecto.Changeset{}} = Instructions.save(c.scope, 0, " ")

    assert {:error, %Ecto.Changeset{}} =
             Instructions.save(c.scope, 0, String.duplicate("é", 12_001))

    assert {:ok, ^fallback} = Instructions.effective()
    assert Repo.aggregate(InstructionRevision, :count) == 0
  end

  test "private runtime file is deny by default and its contents are normalized", _c do
    path = Path.join(System.tmp_dir!(), "assistant-editors-#{Ecto.UUID.generate()}.json")
    on_exit(fn -> File.rm(path) end)
    assert Instructions.load_editors(nil) == []
    assert Instructions.load_editors(path) == []
    File.write!(path, "[\"  EDITOR@example.org  \"]")
    File.chmod!(path, 0o600)
    assert Instructions.load_editors(path) == ["editor@example.org"]
    File.write!(path, "{\"editors\":[\"editor@example.org\"]}")
    assert Instructions.load_editors(path) == []
    File.write!(path, "[42]")
    assert Instructions.load_editors(path) == []
  end

  test "runtime editor files reject symlinks and group or public access", _c do
    path = Path.join(System.tmp_dir!(), "assistant-editors-private-#{Ecto.UUID.generate()}.json")
    link = path <> ".link"

    on_exit(fn ->
      File.rm(link)
      File.rm(path)
    end)

    File.write!(path, "[\"editor@example.org\"]")
    File.chmod!(path, 0o600)
    assert Instructions.load_editors(path) == ["editor@example.org"]
    File.ln_s!(path, link)
    assert Instructions.load_editors(link) == []

    for mode <- [0o640, 0o644, 0o601] do
      File.chmod!(path, mode)
      assert Instructions.load_editors(path) == []
    end
  end

  test "permission loss between mount authorization and fetching content redirects safely", c do
    handler = "instruction-mount-revocation-#{Ecto.UUID.generate()}"
    counter = :atomics.new(1, [])
    caller = self()

    :telemetry.attach(
      handler,
      Repo.config()[:telemetry_prefix] ++ [:query],
      fn _, _, metadata, _ ->
        if self() == caller and metadata[:source] == "users" and
             :atomics.add_get(counter, 1, 1) == 2 do
          Application.put_env(:pauseai_ca, :assistant_instruction_editors, [])
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, current_scope: c.scope}}

    assert {:ok, denied} =
             PauseAiCaWeb.AssistantInstructionsLive.mount(%{"locale" => "en"}, %{}, socket)

    assert {:redirect, %{to: "/"}} = denied.redirected
    assert denied.assigns.instruction == nil
    assert denied.assigns.history == []
    assert :atomics.get(counter, 1) == 2
  end

  defp grant_superadmin(user),
    do: user |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

  defp restore(key, nil), do: Application.delete_env(:pauseai_ca, key)
  defp restore(key, value), do: Application.put_env(:pauseai_ca, key, value)
end
