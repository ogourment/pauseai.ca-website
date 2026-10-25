defmodule PauseAiCa.Chat.SlackTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Chat.{Slack, SlackState, SlackLink, SlackInbox, SlackMessage}
  alias PhoenixCommunity.Slack.OAuth

  setup do
    previous =
      {Application.get_env(:pauseai_ca, :slack_enabled), Application.get_env(:pauseai_ca, :slack)}

    Application.put_env(:pauseai_ca, :slack_enabled, true)

    Application.put_env(:pauseai_ca, :slack, %{
      client_id: "synthetic",
      client_secret: "synthetic-secret",
      app_id: "A1",
      signing_secret: "synthetic-signing",
      team_id: "T1",
      redirect_uri: "https://example.org/slack/callback",
      channel_ids: ["C1", "C2"],
      authorize: fn _, channel, _ -> channel == "C1" end
    })

    on_exit(fn ->
      {enabled, config} = previous

      if is_nil(enabled),
        do: Application.delete_env(:pauseai_ca, :slack_enabled),
        else: Application.put_env(:pauseai_ca, :slack_enabled, enabled)

      if is_nil(config),
        do: Application.delete_env(:pauseai_ca, :slack),
        else: Application.put_env(:pauseai_ca, :slack, config)
    end)

    %{scope: Scope.for_user(user_fixture()), nonce: String.duplicate("n", 43)}
  end

  defp reader(method, token, params) do
    provider_user = String.replace_prefix(token, "xoxp-synthetic-", "")

    result =
      case method do
        "auth.test" ->
          %{"team_id" => "T1", "user_id" => provider_user}

        "users.info" ->
          %{"user" => %{"id" => provider_user, "is_bot" => false, "deleted" => false}}

        "conversations.info" ->
          %{"channel" => %{"id" => params.channel, "is_member" => true}}
      end

    {:ok, 200, Map.put(result, "ok", true)}
  end

  defp authorization(user \\ "U1") do
    %{
      "ok" => true,
      "team" => %{"id" => "T1"},
      "authed_user" => %{
        "id" => user,
        "token_type" => "user",
        "access_token" => "xoxp-synthetic-" <> user,
        "scope" => Enum.join(OAuth.user_scopes(), ",")
      }
    }
  end

  defp connect(c, provider_user \\ "U1") do
    {:ok, started} = Slack.begin_link(c.scope, c.nonce)

    Slack.complete_link(c.scope, started.state, c.nonce, "synthetic-code",
      oauth: fn _, _ -> {:ok, authorization(provider_user)} end,
      read: &reader/3
    )
  end

  defp ingest(event_id, channel, event \\ %{}) do
    payload = %{
      "type" => "event_callback",
      "team_id" => "T1",
      "api_app_id" => "A1",
      "event_id" => event_id,
      "event" =>
        Map.merge(
          %{
            "type" => "message",
            "channel" => channel,
            "ts" => "1800000000.000001",
            "user" => "U1",
            "text" => "Retained needle"
          },
          event
        )
    }

    raw = Jason.encode!(payload)
    ts = Integer.to_string(System.system_time(:second))

    signature =
      "v0=" <>
        Base.encode16(:crypto.mac(:hmac, :sha256, "synthetic-signing", "v0:#{ts}:#{raw}"),
          case: :lower
        )

    assert {:ok, _} = Slack.ingest(raw, ts, signature)
    Repo.get_by!(SlackInbox, event_id: event_id)
  end

  test "durable OAuth state is single-use, account/session-bound and credentials are encrypted",
       c do
    {:ok, started} = Slack.begin_link(c.scope, c.nonce)
    assert URI.decode_query(URI.parse(started.authorization_url).query)["state"] == started.state
    row = Repo.one!(SlackState)
    refute row.state_hash == started.state
    bad_exchange = fn _, _ -> flunk("wrong account/session must not exchange a code") end
    other = Scope.for_user(user_fixture())

    assert {:error, :link_failed} =
             Slack.complete_link(other, started.state, c.nonce, "code", oauth: bad_exchange)

    assert {:error, :link_failed} =
             Slack.complete_link(c.scope, started.state, String.duplicate("x", 43), "code",
               oauth: bad_exchange
             )

    assert {:ok, link} =
             Slack.complete_link(c.scope, started.state, c.nonce, "code",
               oauth: fn _, _ -> {:ok, authorization()} end,
               read: &reader/3
             )

    refute Map.has_key?(link, :token_cipher)
    stored = Repo.one!(SlackLink)
    refute stored.token_cipher =~ "xoxp-synthetic-U1"
    assert stored.user_id == c.scope.user.id

    assert {:error, :link_failed} =
             Slack.complete_link(c.scope, started.state, c.nonce, "code", oauth: bad_exchange)

    assert {:error, :link_failed} = connect(%{c | scope: other})
    assert Repo.aggregate(SlackLink, :count) == 1
  end

  test "failed exchange consumes state and unlinked identities retain their binding", c do
    {:ok, started} = Slack.begin_link(c.scope, c.nonce)

    assert {:error, :link_failed} =
             Slack.complete_link(c.scope, started.state, c.nonce, "code",
               oauth: fn _, _ -> {:error, :network} end
             )

    assert Repo.one!(SlackState).consumed_at
    assert {:ok, link} = connect(c)
    assert {:ok, :unlinked} = Slack.unlink(c.scope, link.revision)
    assert Repo.one!(SlackLink).token_cipher == nil
    other = Scope.for_user(user_fixture())
    assert {:error, :link_failed} = connect(%{c | scope: other})
    assert {:ok, rebound} = connect(c)
    assert rebound.id == link.id
  end

  test "signed inbox is durable/idempotent; retained search intersects website and fresh provider access",
       c do
    {:ok, _} = connect(c)
    row = ingest("Ev1", "C1")
    ingest("Ev1", "C1")
    secret = ingest("Ev2", "C2", %{"text" => "Private needle"})
    assert Repo.aggregate(SlackInbox, :count) == 2
    assert {:ok, :processed} = Slack.process_event(row.id)
    assert {:ok, :processed} = Slack.process_event(row.id)
    assert {:ok, :processed} = Slack.process_event(secret.id)
    assert Repo.aggregate(SlackMessage, :count) == 2
    assert {:ok, [%{text: "Retained needle"}]} = Slack.search(c.scope, "needle", read: &reader/3)
    assert {:error, :access_denied} = Slack.history(c.scope, "C2", read: &reader/3)
    assert {:ok, [%{text: "Retained needle"}]} = Slack.history(c.scope, "C1", read: &reader/3)

    revoked = fn method, token, params ->
      if method == "conversations.info",
        do:
          {:ok, 200,
           %{"ok" => true, "channel" => %{"id" => params.channel, "is_member" => false}}},
        else: reader(method, token, params)
    end

    assert {:ok, []} = Slack.search(c.scope, "needle", read: revoked)
    assert {:error, :access_denied} = Slack.history(c.scope, "C1", read: revoked)
  end

  test "deletion tombstones survive signed replay and bounded history repair", c do
    {:ok, _} = connect(c)
    original = ingest("Original", "C1")
    assert {:ok, :processed} = Slack.process_event(original.id)

    deletion =
      ingest("Deleted", "C1", %{
        "subtype" => "message_deleted",
        "deleted_ts" => "1800000000.000001",
        "event_ts" => "1800000001.000001"
      })

    assert {:ok, :processed} = Slack.process_event(deletion.id)

    history = fn method, token, params ->
      if method == "conversations.history",
        do:
          {:ok, 200,
           %{
             "ok" => true,
             "messages" => [%{"ts" => "1800000000.000001", "text" => "Old content"}],
             "has_more" => true
           }},
        else: reader(method, token, params)
    end

    assert {:ok, %{has_more: true, coverage: :bounded_page_only}} =
             Slack.repair_page(c.scope, "C1", read: history)

    assert Repo.one!(SlackMessage).deleted
    assert Repo.one!(SlackMessage).text == nil
    assert {:ok, []} = Slack.search(c.scope, "content", read: &reader/3)
    refute Enum.any?(Repo.all(SlackInbox), &(Jason.encode!(&1.payload) =~ "needle"))
  end

  test "explicit posting commits sending first and ambiguous delivery never retries", c do
    {:ok, _} = connect(c)
    opts = [read: &reader/3]
    {:ok, draft} = Slack.save_draft(c.scope, "C1", %{"text" => "Synthetic outgoing draft"}, opts)
    {:ok, queued} = Slack.queue(c.scope, draft.id, draft.revision, opts)
    parent = self()

    uncertain = fn _token, _params ->
      assert {:ok, %{status: "sending"}} = Slack.draft(c.scope, draft.id)
      send(parent, :post_attempt)
      {:error, :timeout}
    end

    assert {:ok, %{status: "uncertain", text: "Synthetic outgoing draft"} = outcome} =
             Slack.deliver(c.scope, queued.id, queued.revision, opts ++ [post: uncertain])

    assert_receive :post_attempt

    assert {:error, :invalid_transition} =
             Slack.queue(c.scope, outcome.id, outcome.revision, opts)

    assert {:error, :invalid_transition} =
             Slack.deliver(c.scope, outcome.id, outcome.revision, opts ++ [post: uncertain])

    refute_receive :post_attempt
  end

  test "actual provider receipt settles once, and unlink blocks previously queued drafts", c do
    {:ok, link} = connect(c)
    opts = [read: &reader/3]

    {:ok, draft} =
      Slack.save_draft(
        c.scope,
        "C1",
        %{"text" => "One root", "thread_ts" => "1800000000.000001"},
        opts
      )

    {:ok, queued} = Slack.queue(c.scope, draft.id, draft.revision, opts)

    accepted = fn "xoxp-synthetic-U1", %{channel: "C1", thread_ts: "1800000000.000001"} ->
      {:ok, 200, %{"ok" => true, "channel" => "C1", "ts" => "1800000001.000001"}}
    end

    assert {:ok, %{status: "sent", external_ts: "1800000001.000001"}} =
             Slack.deliver(c.scope, queued.id, queued.revision, opts ++ [post: accepted])

    {:ok, second} =
      Slack.save_draft(c.scope, "C1", %{"text" => "Must not send after unlink"}, opts)

    {:ok, pending} = Slack.queue(c.scope, second.id, second.revision, opts)
    assert {:ok, :unlinked} = Slack.unlink(c.scope, link.revision)

    assert {:error, :access_denied} =
             Slack.deliver(
               c.scope,
               pending.id,
               pending.revision,
               opts ++ [post: fn _, _ -> flunk("unlinked user cannot send") end]
             )

    assert {:ok, %{status: "cancelled"}} = Slack.draft(c.scope, pending.id)
  end

  test "provider outcome is durable even when the feature is disabled during an attempt", c do
    {:ok, _} = connect(c)
    opts = [read: &reader/3]
    {:ok, draft} = Slack.save_draft(c.scope, "C1", %{"text" => "Accepted before shutdown"}, opts)
    {:ok, queued} = Slack.queue(c.scope, draft.id, draft.revision, opts)

    accepted = fn _, _ ->
      Application.put_env(:pauseai_ca, :slack_enabled, false)
      {:ok, 200, %{"ok" => true, "channel" => "C1", "ts" => "1800000001.000001"}}
    end

    assert {:ok, %{status: "sent"}} =
             Slack.deliver(c.scope, queued.id, queued.revision, opts ++ [post: accepted])

    stored = Repo.get!(PauseAiCa.Chat.SlackOutbox, queued.id)
    assert stored.external_ts == "1800000001.000001"
    assert stored.status == "sent"
  end

  test "draft edits require the original revision and do not alter pending content", c do
    {:ok, _} = connect(c)
    opts = [read: &reader/3]
    {:ok, draft} = Slack.save_draft(c.scope, "C1", %{"text" => "Original draft"}, opts)

    assert {:ok, %{text: "Edited draft", revision: 2}} =
             Slack.update_draft(c.scope, draft.id, 1, %{"text" => "Edited draft"}, opts)

    assert {:error, :stale} =
             Slack.update_draft(c.scope, draft.id, 1, %{"text" => "Stale draft"}, opts)

    assert {:ok, %{status: "pending"}} = Slack.queue(c.scope, draft.id, 2, opts)

    assert {:error, :invalid_transition} =
             Slack.update_draft(c.scope, draft.id, 3, %{"text" => "Must stay frozen"}, opts)

    assert {:ok, %{text: "Edited draft"}} = Slack.draft(c.scope, draft.id)
  end
end
