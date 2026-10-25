defmodule PauseAiCa.Chat.Slack do
  @moduledoc """
  Consumer-owned Slack linking, retained reads and explicit outbound boundary.
  Disabled by default. Configuration requires an explicit fresh website-audience
  callback; installation-bot access never authorizes a reader. No worker sends
  automatically. HTTP transports are injectable for isolated synthetic checks.
  """
  import Ecto.Query
  import Ecto.Changeset
  alias PauseAiCa.{Repo, Accounts}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Chat.{SlackState, SlackLink, SlackInbox, SlackMessage, SlackOutbox, SlackHTTP}
  alias PhoenixCommunity.Slack.{OAuth, API, Inbox, Message}
  alias PhoenixCommunity.Outbox
  @salt "slack private credentials v1"

  def configured? do
    c = config()

    Application.get_env(:pauseai_ca, :slack_enabled, false) and
      Enum.all?(
        [:client_id, :client_secret, :team_id, :redirect_uri],
        &(is_binary(c[&1]) and c[&1] != "")
      ) and
      is_list(c[:channel_ids]) and is_function(c[:authorize], 3)
  end

  def begin_link(scope, session_nonce) do
    with :ok <- ready(), {:ok, user} <- user(scope), true <- nonce?(session_nonce) do
      state = random()

      with {:ok, url} <- OAuth.authorization_url(config(), state),
           {:ok, _} <-
             insert(
               change(%SlackState{},
                 user_id: user.id,
                 state_hash: hash(state),
                 session_hash: hash(session_nonce),
                 expires_at: DateTime.add(now(), 600, :second)
               )
             ) do
        {:ok, %{authorization_url: url, state: state}}
      end
    else
      _ -> {:error, :link_unavailable}
    end
  end

  def complete_link(scope, state, session_nonce, code, opts \\ []) do
    with :ok <- ready(),
         {:ok, user} <- user(scope),
         true <-
           nonce?(state) and nonce?(session_nonce) and is_binary(code) and
             byte_size(code) in 1..4096,
         {:ok, _} <- claim_state(user.id, state, session_nonce),
         {:ok, response} <-
           exchange(
             code,
             Keyword.get(opts, :oauth, Map.get(config(), :oauth_transport, &SlackHTTP.oauth/2))
           ),
         {:ok, credentials} <- OAuth.credentials(response, config().team_id),
         :ok <- verify_identity(credentials, reader(opts)),
         {:ok, link} <- save_link(scope, credentials) do
      {:ok, public_link(link)}
    else
      _ -> {:error, :link_failed}
    end
  end

  def link(scope) do
    with :ok <- ready(), {:ok, user} <- user(scope) do
      link = active_link(user.id)
      {:ok, if(link, do: public_link(link), else: nil)}
    end
  end

  def unlink(scope, revision) do
    with :ok <- ready(), {:ok, user} <- user(scope) do
      tx(fn ->
        link =
          Repo.one(
            from(l in SlackLink,
              where: l.user_id == ^user.id and l.team_id == ^config().team_id and l.active,
              lock: "FOR UPDATE"
            ),
            log: false
          )

        require!(link && link.revision == revision, :stale)
        require!(match?({:ok, _}, user(scope)), :forbidden)

        update!(
          change(link,
            active: false,
            token_cipher: nil,
            refresh_cipher: nil,
            revision: link.revision + 1
          )
        )

        Repo.update_all(
          from(o in SlackOutbox, where: o.link_id == ^link.id and o.status == "pending"),
          [set: [status: "cancelled"]],
          log: false
        )

        :unlinked
      end)
    end
  end

  def channels(scope, opts \\ []) do
    with :ok <- ready(), {:ok, _} <- user(scope) do
      {:ok,
       Enum.filter(config().channel_ids, fn channel ->
         match?({:ok, _}, access(scope, channel, :read, opts))
       end)}
    end
  end

  def channel_name(channel), do: Map.get(config()[:channel_names] || %{}, channel, channel)

  def drafts(scope) do
    with :ok <- ready(), {:ok, user} <- user(scope) do
      {:ok,
       Repo.all(
         from(o in SlackOutbox,
           where: o.user_id == ^user.id,
           order_by: [desc: o.updated_at],
           limit: 50
         ),
         log: false
       )
       |> Enum.map(&public_draft/1)}
    end
  end

  def permalink(scope, channel, timestamp, opts \\ []) do
    with true <- timestamp?(timestamp),
         {:ok, link} <- access(scope, channel, :read, opts),
         {:ok, %{"permalink" => url}} <-
           API.read(
             "chat.getPermalink",
             link.token,
             %{channel: channel, message_ts: timestamp},
             reader(opts)
           ),
         %URI{scheme: "https", host: host, userinfo: nil} <- URI.parse(url),
         true <- host == "slack.com" or String.ends_with?(host, ".slack.com") do
      {:ok, url}
    else
      _ -> {:error, :source_unavailable}
    end
  end

  def history(scope, channel, opts \\ []) do
    with {:ok, _} <- access(scope, channel, :read, opts) do
      {:ok,
       Repo.all(
         from(m in SlackMessage,
           where: m.team_id == ^config().team_id and m.channel_id == ^channel and not m.deleted,
           order_by: [desc: fragment("?::numeric", m.external_ts)],
           limit: 50,
           select:
             map(m, [
               :id,
               :channel_id,
               :external_ts,
               :text,
               :thread_ts,
               :provider_user_id,
               :bot_id
             ])
         ),
         log: false
       )}
    end
  end

  def search(scope, term, opts \\ [])

  def search(scope, term, opts) when is_binary(term) and byte_size(term) in 1..200 do
    with {:ok, channels} <- channels(scope, opts) do
      query =
        "%" <>
          (term
           |> String.replace("\\", "\\\\")
           |> String.replace("%", "\\%")
           |> String.replace("_", "\\_")) <> "%"

      {:ok,
       Repo.all(
         from(m in SlackMessage,
           where:
             m.team_id == ^config().team_id and m.channel_id in ^channels and not m.deleted and
               ilike(m.text, ^query),
           order_by: [desc: fragment("?::numeric", m.external_ts)],
           limit: 50,
           select: map(m, [:id, :channel_id, :external_ts, :text, :thread_ts, :provider_user_id])
         ),
         log: false
       )}
    end
  end

  def search(_, _, _), do: {:error, :invalid_query}

  def ingest(raw, timestamp, signature) do
    if configured?() do
      Inbox.receive_event(raw, timestamp, signature, config(), fn envelope ->
        row =
          change(%SlackInbox{},
            team_id: envelope.team_id,
            event_id: envelope.event_id,
            payload: envelope.payload
          )

        case Repo.insert(row,
               on_conflict: :nothing,
               conflict_target: [:team_id, :event_id],
               returning: true,
               log: false
             ) do
          {:ok, %{id: id}} ->
            # The existing immutable envelope is authoritative on duplicate delivery.
            if Repo.get_by!(SlackInbox, [team_id: envelope.team_id, event_id: envelope.event_id],
                 log: false
               ).id == id, do: :inserted, else: :duplicate

          _ ->
            :failed
        end
      end)
    else
      {:error, :not_configured}
    end
  end

  @doc "Internal inbox worker entry; never expose as an unauthenticated HTTP action."
  def process_event(id) do
    with :ok <- ready() do
      tx(fn ->
        envelope =
          Repo.one(from(e in SlackInbox, where: e.id == ^id, lock: "FOR UPDATE"), log: false)

        require!(envelope && envelope.team_id == config().team_id, :not_found)

        if envelope.status == "pending" do
          event = envelope.payload["event"]
          require!(event["channel"] in config().channel_ids, :channel_not_selected)

          case project(envelope.team_id, event) do
            {:ok, _} ->
              update!(
                change(envelope,
                  status: "processed",
                  payload: %{"type" => "processed_message"},
                  processed_at: now()
                )
              )

            _ ->
              update!(
                change(envelope,
                  status: "ignored",
                  payload: %{"type" => "unsupported_message"},
                  processed_at: now()
                )
              )
          end
        end

        :processed
      end)
    end
  end

  @doc "Internal bounded inbox projection; no provider call and no outgoing dispatch."
  def process_pending do
    if configured?() do
      ids =
        Repo.all(
          from(e in SlackInbox,
            where: e.team_id == ^config().team_id and e.status == "pending",
            order_by: e.inserted_at,
            limit: 5,
            select: e.id
          ),
          log: false
        )

      for id <- ids do
        case process_event(id) do
          {:ok, _} ->
            :ok

          {:error, _} ->
            Repo.update_all(
              from(e in SlackInbox, where: e.id == ^id and e.status == "pending"),
              [set: [status: "blocked"]],
              log: false
            )
        end
      end

      :ok
    else
      {:error, :not_configured}
    end
  end

  def repair_page(scope, channel, opts \\ []) do
    with {:ok, link} <- access(scope, channel, :read, opts),
         {:ok, body} <-
           API.read(
             "conversations.history",
             link.token,
             %{channel: channel, limit: 50},
             reader(opts)
           ),
         %{"messages" => messages} when is_list(messages) <- body,
         true <- length(messages) <= 50 do
      tx(fn ->
        for message <- messages do
          {:ok, _} =
            project(
              link.team_id,
              Map.merge(message, %{"type" => "message", "channel" => channel})
            )
        end

        %{
          captured: length(messages),
          has_more: body["has_more"] == true,
          coverage: :bounded_page_only
        }
      end)
    else
      _ -> {:error, :repair_unavailable}
    end
  end

  def repair_thread(scope, channel, thread, opts \\ []) do
    with true <- timestamp?(thread),
         {:ok, link} <- access(scope, channel, :read, opts),
         {:ok, %{"messages" => messages} = body} <-
           API.read(
             "conversations.replies",
             link.token,
             %{channel: channel, ts: thread, limit: 50},
             reader(opts)
           ),
         true <- is_list(messages) and length(messages) <= 50 do
      tx(fn ->
        for message <- messages do
          case project(
                 link.team_id,
                 Map.merge(message, %{"type" => "message", "channel" => channel})
               ) do
            {:ok, _} -> :ok
            _ -> Repo.rollback(:invalid_source_message)
          end
        end

        %{
          captured: length(messages),
          has_more: body["has_more"] == true,
          coverage: :bounded_thread_only
        }
      end)
    else
      _ -> {:error, :repair_unavailable}
    end
  end

  def save_draft(scope, channel, attrs, opts \\ []) do
    with {:ok, link} <- access(scope, channel, :post, opts) do
      %SlackOutbox{}
      |> cast(attrs, [:text, :thread_ts])
      |> validate_required([:text])
      |> validate_length(:text, max: 4000)
      |> validate_change(:thread_ts, fn :thread_ts, value ->
        if timestamp?(value), do: [], else: [thread_ts: "must identify a Slack thread"]
      end)
      |> put_change(:user_id, scope.user.id)
      |> put_change(:link_id, link.id)
      |> put_change(:link_revision, link.revision)
      |> put_change(:team_id, link.team_id)
      |> put_change(:channel_id, channel)
      |> insert()
      |> case do
        {:ok, draft} -> {:ok, public_draft(draft)}
        error -> error
      end
    end
  end

  def update_draft(scope, id, revision, attrs, opts \\ []) do
    with {:ok, existing} <- own_draft(scope, id),
         {:ok, _} <- access(scope, existing.channel_id, :post, opts) do
      mutate_draft(scope, id, revision, fn draft ->
        require!(draft.status in ["draft", "failed"], :invalid_transition)

        cs =
          draft
          |> cast(attrs, [:text])
          |> validate_required([:text])
          |> validate_length(:text, max: 4000)

        if cs.valid?,
          do: update!(put_change(cs, :revision, draft.revision + 1)),
          else: Repo.rollback(cs)
      end)
    end
  end

  def cancel_draft(scope, id, revision),
    do: mutate_draft(scope, id, revision, &transition!(&1, :cancel, %{explicit: true}))

  def draft(scope, id) do
    with :ok <- ready(),
         {:ok, user} <- user(scope),
         true <- uuid?(id),
         %SlackOutbox{} = draft <-
           Repo.get_by(SlackOutbox, [id: id, user_id: user.id], log: false) do
      {:ok, public_draft(draft)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "Queue only in response to the linked member's explicit review/send action."
  def queue(scope, id, revision, opts \\ []) do
    with {:ok, draft} <- own_draft(scope, id),
         {:ok, link} <- access(scope, draft.channel_id, :post, opts) do
      authorized_mutation(scope, id, revision, link, fn draft ->
        require!(draft.link_id == link.id and draft.link_revision == link.revision, :link_changed)

        transition!(draft, if(draft.status == "failed", do: :retry, else: :queue), %{
          explicit: true,
          authorized: true
        })
      end)
    end
  end

  @doc "A trusted consumer action sends one pending record; never a blind retry loop."
  def deliver(scope, id, revision, opts \\ []) do
    with {:ok, draft} <- own_draft(scope, id),
         {:ok, link} <- access(scope, draft.channel_id, :post, opts),
         {:ok, sending} <-
           authorized_mutation(scope, id, revision, link, fn draft ->
             require!(
               draft.link_id == link.id and draft.link_revision == link.revision,
               :link_changed
             )

             transition!(draft, :claim, %{authorized: true})
           end) do
      params = %{channel: sending.channel_id, text: sending.text}

      params =
        if sending.thread_ts, do: Map.put(params, :thread_ts, sending.thread_ts), else: params

      result =
        send_once(
          link.token,
          params,
          Keyword.get(opts, :post, Map.get(config(), :post_transport, &SlackHTTP.post_message/2))
        )

      settle_attempt(id, sending.revision, fn locked ->
        case result do
          {:ok, 200, %{"ok" => true, "channel" => channel, "ts" => ts}}
          when channel == sending.channel_id ->
            if timestamp?(ts),
              do: transition!(locked, :accepted, %{verified_receipt: true}, external_ts: ts),
              else: transition!(locked, :ambiguous, %{})

          {:ok, status, %{"ok" => false}} when status in [200, 400, 401, 403, 429] ->
            transition!(locked, :rejected, %{definite_rejection: true})

          _ ->
            transition!(locked, :ambiguous, %{})
        end
      end)
    end
  end

  @doc "Recover a crashed sending attempt to uncertain, without any provider call."
  def recover_attempt(scope, id, revision),
    do: mutate_draft(scope, id, revision, &transition!(&1, :recover, %{}))

  defp access(scope, channel, action, opts) do
    with :ok <- ready(),
         {:ok, user} <- user(scope),
         true <- channel in config().channel_ids,
         true <- config().authorize.(Scope.for_user(user), channel, action) == true,
         %SlackLink{} = link <- active_link(user.id),
         true <- is_nil(link.expires_at) or DateTime.compare(link.expires_at, now()) == :gt,
         {:ok, token} <-
           Phoenix.Token.decrypt(PauseAiCaWeb.Endpoint, @salt, link.token_cipher,
             max_age: :infinity
           ),
         proof = %{team_id: link.team_id, user_id: link.provider_user_id, token: token},
         {:ok, _} <- API.authorize_channel(proof, channel, reader(opts)) do
      {:ok, %{id: link.id, revision: link.revision, team_id: link.team_id, token: token}}
    else
      _ -> {:error, :access_denied}
    end
  rescue
    _ -> {:error, :access_denied}
  end

  defp claim_state(user_id, state, nonce) do
    tx(fn ->
      row =
        Repo.one(from(s in SlackState, where: s.state_hash == ^hash(state), lock: "FOR UPDATE"),
          log: false
        )

      require!(
        row && row.user_id == user_id && row.session_hash == hash(nonce) &&
          is_nil(row.consumed_at) && DateTime.compare(row.expires_at, now()) == :gt,
        :invalid_state
      )

      update!(change(row, consumed_at: now()))
    end)
  end

  defp exchange(code, transport) do
    transport.(code, config())
  rescue
    _ -> {:error, :authorization_failed}
  catch
    :exit, _ -> {:error, :authorization_failed}
  end

  defp verify_identity(credentials, transport) do
    with {:ok, %{"team_id" => team, "user_id" => id}} <-
           API.read("auth.test", credentials.access_token, %{}, transport),
         true <- team == credentials.team_id and id == credentials.user_id,
         {:ok, %{"user" => %{"id" => ^id, "deleted" => false, "is_bot" => false}}} <-
           API.read("users.info", credentials.access_token, %{user: id}, transport) do
      :ok
    else
      _ -> {:error, :identity_unverified}
    end
  end

  defp save_link(scope, credentials) do
    tx(fn ->
      {:ok, user} = user(scope)

      Repo.query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        ["slack-link:" <> credentials.team_id],
        log: false
      )

      existing =
        Repo.get_by(
          SlackLink,
          [team_id: credentials.team_id, provider_user_id: credentials.user_id],
          log: false
        )

      require!(!existing || existing.user_id == user.id, :identity_collision)
      active = active_link(user.id)
      require!(!active || active.provider_user_id == credentials.user_id, :unlink_first)

      link =
        existing ||
          %SlackLink{
            user_id: user.id,
            team_id: credentials.team_id,
            provider_user_id: credentials.user_id
          }

      attrs = [
        active: true,
        token_cipher: encrypt(credentials.access_token),
        refresh_cipher: encrypt(credentials.refresh_token),
        scopes: credentials.scopes,
        expires_at:
          if(credentials.expires_in, do: DateTime.add(now(), credentials.expires_in, :second)),
        revision: if(existing, do: existing.revision + 1, else: 1)
      ]

      case Repo.insert_or_update(change(link, attrs), log: false) do
        {:ok, result} -> result
        {:error, _} -> Repo.rollback(:link_failed)
      end
    end)
  end

  defp project(team, event) do
    with {:ok, incoming} <- Message.normalize(team, event) do
      {^team, channel, ts} = incoming.key

      Repo.query!(
        "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
        ["slack-message:" <> team <> ":" <> channel <> ":" <> ts],
        log: false
      )

      current =
        Repo.get_by(SlackMessage, [team_id: team, channel_id: channel, external_ts: ts],
          log: false
        )

      prior =
        if current,
          do: %{
            key: incoming.key,
            version: current.version,
            text: current.text,
            deleted: current.deleted,
            user_id: current.provider_user_id,
            bot_id: current.bot_id,
            thread_ts: current.thread_ts
          }

      {:ok, merged} = Message.merge(prior, incoming)

      attrs = [
        version: merged.version,
        text: merged.text,
        deleted: merged.deleted,
        provider_user_id: merged.user_id,
        bot_id: merged.bot_id,
        thread_ts: merged.thread_ts
      ]

      Repo.insert_or_update(
        change(
          current || %SlackMessage{team_id: team, channel_id: channel, external_ts: ts},
          attrs
        ),
        log: false
      )
    end
  end

  defp own_draft(scope, id) do
    with :ok <- ready(),
         {:ok, user} <- user(scope),
         true <- uuid?(id),
         %SlackOutbox{} = draft <-
           Repo.get_by(SlackOutbox, [id: id, user_id: user.id], log: false) do
      {:ok, draft}
    else
      _ -> {:error, :not_found}
    end
  end

  defp mutate_draft(scope, id, revision, fun) do
    with {:ok, _} <- own_draft(scope, id) do
      tx(fn ->
        draft =
          Repo.one!(
            from(o in SlackOutbox,
              where: o.id == ^id and o.user_id == ^scope.user.id,
              lock: "FOR UPDATE"
            ),
            log: false
          )

        require!(draft.revision == revision, :stale)
        require!(match?({:ok, _}, user(scope)), :forbidden)
        fun.(draft) |> public_draft()
      end)
    end
  end

  defp authorized_mutation(scope, id, revision, link, fun) do
    tx(fn ->
      current =
        Repo.one(from(l in SlackLink, where: l.id == ^link.id, lock: "FOR UPDATE"), log: false)

      require!(current && current.active && current.revision == link.revision, :link_changed)
      {:ok, fresh} = user(scope)

      draft =
        Repo.one(
          from(o in SlackOutbox,
            where: o.id == ^id and o.user_id == ^fresh.id,
            lock: "FOR UPDATE"
          ),
          log: false
        )

      require!(draft && draft.revision == revision, :stale)

      require!(
        config().authorize.(Scope.for_user(fresh), draft.channel_id, :post) == true,
        :forbidden
      )

      fun.(draft) |> public_draft()
    end)
  end

  defp settle_attempt(id, revision, fun) do
    tx(fn ->
      draft =
        Repo.one!(from(o in SlackOutbox, where: o.id == ^id, lock: "FOR UPDATE"), log: false)

      require!(draft.revision == revision and draft.status == "sending", :stale)
      fun.(draft) |> public_draft()
    end)
  end

  defp transition!(draft, action, facts, attrs \\ []) do
    case Outbox.transition(draft.status, action, facts) do
      {:ok, status} ->
        update!(change(draft, attrs ++ [status: status, revision: draft.revision + 1]))

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp send_once(token, params, transport) do
    transport.(token, params)
  rescue
    _ -> {:error, :uncertain}
  catch
    :exit, _ -> {:error, :uncertain}
  end

  defp config, do: Application.get_env(:pauseai_ca, :slack, %{})
  defp ready, do: if(configured?(), do: :ok, else: {:error, :not_configured})

  defp user(%Scope{user: %{id: id}}) do
    case Repo.get(Accounts.User, id) do
      %{confirmed_at: at} = user when not is_nil(at) -> {:ok, user}
      _ -> {:error, :forbidden}
    end
  end

  defp user(_), do: {:error, :forbidden}

  defp active_link(id),
    do: Repo.get_by(SlackLink, [user_id: id, team_id: config().team_id, active: true], log: false)

  defp reader(opts),
    do: Keyword.get(opts, :read, Map.get(config(), :read_transport, &SlackHTTP.read/3))

  defp public_link(link),
    do: Map.take(link, [:id, :team_id, :provider_user_id, :active, :revision, :expires_at])

  defp public_draft(draft),
    do:
      Map.take(draft, [
        :id,
        :user_id,
        :channel_id,
        :thread_ts,
        :text,
        :status,
        :external_ts,
        :permalink,
        :revision
      ])

  defp encrypt(nil), do: nil
  defp encrypt(value), do: Phoenix.Token.encrypt(PauseAiCaWeb.Endpoint, @salt, value)
  defp insert(cs), do: Repo.insert(cs, log: false)
  defp update!(cs), do: Repo.update!(cs, log: false)
  defp tx(fun), do: Repo.transaction(fun, log: false)
  defp require!(condition, reason), do: if(!condition, do: Repo.rollback(reason))
  defp now, do: DateTime.utc_now()
  defp hash(value), do: :crypto.hash(:sha256, value)
  defp random, do: Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  defp nonce?(value), do: is_binary(value) and byte_size(value) in 32..128
  defp uuid?(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp timestamp?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9]+\.[0-9]{6}\z/, value)
end
