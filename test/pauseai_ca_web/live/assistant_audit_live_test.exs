defmodule PauseAiCaWeb.AssistantAuditLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  import Ecto.Query
  alias PauseAiCa.{Accounts, Assistant, Repo}
  alias PauseAiCa.Assistant.Audit
  alias PhoenixAgentAssistant.Store
  alias PhoenixAgentAssistant.Store.{AuditEntry, Stream}

  setup do
    old = Application.fetch_env(:pauseai_ca, :agent_assistant)
    config = PauseAiCa.AssistantFixtures.configuration(self())
    Application.put_env(:pauseai_ca, :agent_assistant, config)
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    other = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    member = user_fixture()

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:pauseai_ca, :agent_assistant, value)
        :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
      end
    end)

    %{
      admin: admin,
      other: other,
      member: member,
      scope: Accounts.Scope.for_user(admin),
      config: config
    }
  end

  test "direct nonadmin access is denied and role revocation clears the active viewer", c do
    assert build_conn()
           |> log_in_user(c.member)
           |> get("/admin/assistant/activity?locale=en")
           |> response(403) == "superadmin required"

    assert {:error, :forbidden} = Audit.page(Accounts.Scope.for_user(c.member), %{})
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/admin/assistant/activity?locale=en")
    Repo.update!(Ecto.Changeset.change(c.admin, superadmin: false))
    render_click(view, "first")
    assert_redirect(view, "/")
    refute_receive {:assistant_generated, _, _}
  end

  test "protected request route shows typed hold explanation without message or review internals",
       c do
    reference = Ecto.UUID.generate()

    record(c, c.other.id, %{
      "kind" => "safety_review",
      "request_id" => reference,
      "direction" => "output",
      "decision" => %{
        "action" => "review",
        "policy" => "text_coaching_v1",
        "jev" => %{
          "probabilities" => %{"low" => 0.87, "block" => 0.01},
          "model" => "PRIVATE-MODEL"
        },
        "moderation" => %{"flagged" => false, "categories" => %{"PRIVATE" => false}}
      },
      "text" => "PRIVATE-ANSWER",
      "error" => "PRIVATE-ERROR"
    })

    record(c, c.other.id, %{
      "kind" => "request_held",
      "request_id" => reference,
      "reason" => "output_safety_review_required"
    })

    unrelated =
      record(c, c.other.id, %{"kind" => "request", "request_id" => Ecto.UUID.generate()})

    path =
      "/admin/assistant/activity/requests/#{reference}?locale=en&event_id=untrusted-not-a-filter"

    assert log_in_user(build_conn(), c.member) |> get(path) |> response(403) ==
             "superadmin required"

    {:ok, view, html} = live(log_in_user(c.conn, c.admin), path)
    assert has_element?(view, "#assistant-request-timeline", "Request activity")
    assert html =~ "0.87" and html =~ "0.01"
    assert html =~ "Answer withheld: output review needs attention."
    assert html =~ "independent yes-probabilities"
    refute html =~ "PRIVATE"
    refute has_element?(view, "#assistant-audit-table-#{unrelated.id}")
    refute has_element?(view, "button", "Approve")
  end

  test "request pagination keeps exact reference and fresh revocation denies further events", c do
    reference = Ecto.UUID.generate()
    for _ <- 1..27, do: record(c, c.other.id, %{"kind" => "request", "request_id" => reference})

    {:ok, view, _} =
      live(
        log_in_user(c.conn, c.admin),
        "/admin/assistant/activity/requests/#{reference}?locale=en"
      )

    assert has_element?(view, "#assistant-audit-next")
    render_click(view, "next")
    patch = assert_patch(view)
    assert patch =~ "/requests/#{reference}?"
    assert patch =~ "cursor="
    assert has_element?(view, "#assistant-request-timeline")
    Repo.update!(Ecto.Changeset.change(c.admin, superadmin: false))
    render_click(view, "first")
    assert_redirect(view, "/")
  end

  test "request filter rejects malformed references and authenticated-row tampering", c do
    assert {:error, :audit_unavailable} = Audit.page(c.scope, %{"request_ref" => "not-a-uuid"})
    reference = Ecto.UUID.generate()
    row = record(c, c.other.id, %{"kind" => "request", "request_id" => reference})

    Repo.update!(
      Ecto.Changeset.change(row, envelope: Map.put(row.envelope, "ciphertext", "tampered"))
    )

    assert {:error, :audit_unavailable} = Audit.page(c.scope, %{"request_ref" => reference})
    refute_receive {:assistant_generated, _, _}
  end

  test "metadata hides all private content and other namespaces; access is durably recorded while OFF",
       c do
    row =
      record(c, c.other.id, %{
        "kind" => "request",
        "text" => "PRIVATE-PROMPT",
        "context" => %{"secret" => "PRIVATE-CONTEXT"},
        "attachments" => ["PRIVATE-IMAGE"]
      })

    foreign = Store.new(Repo, "foreign-synthetic-namespace")

    {:ok, %{entry: foreign_row}} =
      Store.record(
        foreign,
        c.other.id,
        Ecto.UUID.generate(),
        %{"kind" => "request"},
        c.config[:audit_keys]
      )

    assert {:ok, page} = Audit.page(c.scope, %{})
    assert Enum.any?(page.rows, &(&1.id == row.id))
    assert Enum.any?(page.rows, &(&1.kind == "audit_viewed" and &1.actor_id == c.admin.id))
    refute Enum.any?(page.rows, &(&1.id == foreign_row.id))

    assert Repo.exists?(
             from(s in Stream,
               where:
                 s.namespace == ^Assistant.store().namespace and s.actor_id == ^c.admin.id and
                   s.reference == "audit-access"
             )
           )

    refute Store.enabled?(Assistant.store())
    {:ok, view, html} = live(log_in_user(c.conn, c.admin), "/admin/assistant/activity?locale=en")
    assert has_element?(view, "#assistant-audit-table")
    refute html =~ "PRIVATE"
    refute has_element?(view, "a[download]")
    refute_receive {:assistant_generated, _, _}
  end

  test "keyset filters persist and older pages are bounded without repeated audit rows", c do
    rows =
      for _ <- 1..31, do: record(c, c.other.id, %{"kind" => "mode_changed", "mode" => "fast"})

    {:ok, view, _} =
      live(
        log_in_user(c.conn, c.admin),
        "/admin/assistant/activity?locale=en&actor=#{c.other.id}&kind=mode_changed"
      )

    first = render(view)
    first_ids = Enum.filter(rows, &String.contains?(first, &1.id)) |> Enum.map(& &1.id)
    assert length(first_ids) == 25
    view |> element("#assistant-audit-next") |> render_click()
    second = render(view)
    second_ids = Enum.filter(rows, &String.contains?(second, &1.id)) |> Enum.map(& &1.id)
    assert length(second_ids) == 6
    assert MapSet.disjoint?(MapSet.new(first_ids), MapSet.new(second_ids))
    assert has_element?(view, "#audit-kind option[value='mode_changed'][selected]")
    assert has_element?(view, "#audit-actor option[value='#{c.other.id}'][selected]")
    refute has_element?(view, "#assistant-audit-next")
  end

  test "tampering fails closed and failed access logging discloses no records", c do
    row = record(c, c.other.id, %{"kind" => "request", "text" => "PRIVATE"})

    Repo.update!(
      Ecto.Changeset.change(row,
        envelope: Map.put(row.envelope, "ciphertext", Base.encode64("tampered"))
      )
    )

    assert {:error, :audit_unavailable} = Audit.page(c.scope, %{})
    {:ok, view, html} = live(log_in_user(c.conn, c.admin), "/admin/assistant/activity?locale=en")
    assert has_element?(view, "[role=alert]")
    refute has_element?(view, "#assistant-audit-table")
    refute html =~ "PRIVATE"

    Repo.get!(AuditEntry, row.id)
    |> Ecto.Changeset.change(envelope: row.envelope)
    |> Repo.update!()

    assert Repo.aggregate(PhoenixAgentAssistant.Store.Alert, :count) == 1

    Repo.get!(AuditEntry, row.id)
    |> Ecto.Changeset.change(envelope: row.envelope)
    |> Repo.update!()

    {:ok, %{entry: access}} =
      Store.record(
        Assistant.store(),
        c.admin.id,
        Ecto.UUID.generate(),
        %{"kind" => "audit_viewed"},
        c.config[:audit_keys],
        stream: "audit-access"
      )

    Repo.update!(
      Ecto.Changeset.change(access, envelope: Map.put(access.envelope, "ciphertext", "invalid"))
    )

    count = Repo.aggregate(AuditEntry, :count)
    assert {:error, :audit_unavailable} = Audit.page(c.scope, %{})
    assert Repo.aggregate(AuditEntry, :count) == count + 1
    assert Repo.aggregate(PhoenixAgentAssistant.Store.Alert, :count) == 2
    assert {:error, :audit_unavailable} = Audit.page(c.scope, %{})
    assert Repo.aggregate(AuditEntry, :count) == count + 1
    assert Repo.aggregate(PhoenixAgentAssistant.Store.Alert, :count) == 2
    refute_receive {:assistant_generated, _, _}
  end

  test "historical actors remain labelled after demotion and other namespaces are excluded", c do
    record(c, c.other.id, %{"kind" => "mode_changed"})
    Repo.update!(Ecto.Changeset.change(c.other, superadmin: false, confirmed_at: nil))
    foreign = Store.new(Repo, "other-namespace")

    {:ok, _} =
      Store.record(
        foreign,
        c.member.id,
        Ecto.UUID.generate(),
        %{"kind" => "request"},
        c.config[:audit_keys]
      )

    assert {:ok, %{choices: choices, labels: labels}} = Audit.accounts(c.scope, [c.other.id])
    assert labels[c.other.id] == c.other.email
    assert Enum.any?(choices, &(&1.id == c.other.id))
    refute Enum.any?(choices, &(&1.id == c.member.id))
    {:ok, view, html} = live(log_in_user(c.conn, c.admin), "/admin/assistant/activity?locale=en")
    assert has_element?(view, "#audit-actor option[value='#{c.other.id}']")
    assert html =~ c.other.email
  end

  test "selected recorded actor beyond 100 choices remains visible without exposing unrecorded accounts",
       c do
    for index <- 1..101 do
      actor = "00000000-0000-0000-0000-" <> String.pad_leading(Integer.to_string(index), 12, "0")
      record(c, actor, %{"kind" => "mode_changed"})
    end

    record(c, c.other.id, %{"kind" => "mode_changed"})
    assert {:ok, %{choices: initial}} = Audit.accounts(c.scope)
    assert length(initial) == 100
    refute Enum.any?(initial, &(&1.id == c.other.id))
    assert {:ok, %{choices: choices, labels: labels}} = Audit.accounts(c.scope, [], c.other.id)
    assert length(choices) == 100
    assert List.last(choices).id == c.other.id
    assert labels[c.other.id] == c.other.email

    for locale <- ["en", "fr"] do
      {:ok, view, html} =
        live(
          log_in_user(build_conn(), c.admin),
          "/admin/assistant/activity?locale=#{locale}&actor=#{c.other.id}"
        )

      assert has_element?(
               view,
               "#audit-actor option[value='#{c.other.id}'][selected]",
               c.other.email
             )

      assert Enum.count(LazyHTML.query(LazyHTML.from_document(html), "#audit-actor option")) ==
               101
    end

    assert {:error, :invalid_actor_filter} = Audit.accounts(c.scope, [], c.member.id)
    foreign = Store.new(Repo, "foreign-actor-choice")

    {:ok, _} =
      Store.record(
        foreign,
        c.member.id,
        Ecto.UUID.generate(),
        %{"kind" => "request"},
        c.config[:audit_keys]
      )

    assert {:error, :invalid_actor_filter} = Audit.accounts(c.scope, [], c.member.id)
    assert {:error, :invalid_actor_filter} = Audit.accounts(c.scope, [], "not-an-actor")

    assert {:error, {:redirect, %{to: "/"}}} =
             live(
               log_in_user(build_conn(), c.admin),
               "/admin/assistant/activity?actor=#{c.member.id}"
             )
  end

  test "assistant pages supply the authorized Admin menu root in both editions", c do
    for locale <- ["en", "fr"], path <- ["/admin/assistant", "/admin/assistant/activity"] do
      {:ok, _view, html} = live(log_in_user(build_conn(), c.admin), path <> "?locale=" <> locale)

      [context] =
        html
        |> LazyHTML.from_document()
        |> LazyHTML.query("#journey-breadcrumbs")
        |> LazyHTML.attribute("data-journey-context")

      assert Jason.decode!(context) == %{
               "roots" => [%{"href" => "/admin/dashboard?locale=#{locale}", "label" => "Admin"}],
               "sections" => []
             }
    end

    assert PauseAiCaWeb.Navigation.assistant_breadcrumb_context(
             Accounts.Scope.for_user(c.member),
             "en"
           ).roots == []

    Repo.update!(Ecto.Changeset.change(c.admin, superadmin: false))
    assert PauseAiCaWeb.Navigation.assistant_breadcrumb_context(c.scope, "fr").roots == []
  end

  test "missing audit configuration blocks disclosure without inventing an integrity incident",
       c do
    record(c, c.other.id, %{"kind" => "request", "text" => "PRIVATE"})
    Application.put_env(:pauseai_ca, :agent_assistant, Keyword.delete(c.config, :audit_keys))
    assert {:error, :audit_unavailable} = Audit.page(c.scope, %{})
    assert Repo.aggregate(PhoenixAgentAssistant.Store.Alert, :count) == 0
  end

  test "coaching mail entry is read-only until the human chooses Compose", c do
    count = Repo.aggregate(PauseAiCa.Newsletters.Draft, :count)
    {:ok, view, _} = live(log_in_user(c.conn, c.admin), "/manage/mail?locale=en")
    assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == count
    assert has_element?(view, "#mail-new-draft", "Compose")
    view |> element("#mail-new-draft") |> render_click()
    assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == count + 1
  end

  defp record(c, actor, event) do
    {:ok, %{entry: entry}} =
      Store.record(Assistant.store(), actor, Ecto.UUID.generate(), event, c.config[:audit_keys])

    entry
  end
end
