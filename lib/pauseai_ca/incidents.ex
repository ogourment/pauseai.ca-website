defmodule PauseAiCa.Incidents do
  @moduledoc "Bounded operational incidents. Never accept exception messages, URLs, emails or stacks as incident fields."
  alias PauseAiCa.Repo
  @browser_kinds ~w(exception rejection script_load socket_recovery)
  @classes ~w(Error TypeError ReferenceError SyntaxError RangeError SecurityError NetworkError unknown)
  @surfaces ~w(groups profile manage admin public)
  @table :pauseai_incident_buffer

  def browser(%{"kind" => kind, "class" => class, "surface" => surface} = params)
      when kind in @browser_kinds and class in @classes and surface in @surfaces do
    line =
      if is_integer(params["line"]) and params["line"] in 1..500_000, do: params["line"], else: 0

    record("browser", kind <> "/" <> class, "#{surface}:#{line}", nil)
  end

  def browser(_), do: :ignored

  def confirmation(:recipient_delivery_hold, _ref), do: :ignored

  def confirmation(reason, ref) do
    category =
      case reason do
        :staging_admin_required -> "staging_actor_required"
        :mail_environment_blocked -> "mail_environment_blocked"
        _ -> "dispatch_failed"
      end

    record("mail", category, "participation.confirmation", ref)
  end

  def server(category, location), do: record("server", category, location, nil)

  # The caller never touches the database or performs network I/O. Limit unique
  # fingerprints separately so anonymous reports cannot evict server incidents.
  defp record(source, category, location, ref) do
    key = {source, category, location}

    if :ets.member(@table, key) or
         :ets.info(@table, :size) < if(source == "browser", do: 128, else: 256) do
      :ets.update_counter(@table, key, {2, 1}, {key, 0, ref})
      :ok
    else
      :limited
    end
  rescue
    ArgumentError -> :unavailable
  end

  def flush do
    for {key = {source, category, location}, count, ref} <- :ets.tab2list(@table) do
      persist(source, category, location, count, ref)
      # Concurrent arrivals remain for the next flush.
      :ets.update_counter(@table, key, {2, -count})
      :ets.select_delete(@table, [{{key, 0, :_}, [], [true]}])
    end

    :ok
  end

  def environment, do: to_string(PauseAiCa.MailSafety.environment())

  defp persist(source, category, location, count, ref) do
    release =
      case AcceptanceHarness.Health.payload()[:release_id] do
        id when is_binary(id) and id not in ["", "unknown"] -> id
        _ -> to_string(Application.spec(:pauseai_ca, :vsn))
      end

    Repo.query!(
      """
      INSERT INTO operational_incidents AS i
        (environment,source,category,location,release,occurrences,request_ref,last_seen,next_attempt)
      VALUES ($1,$2,$3,$4,$5,$6,$7,date_trunc('second',timezone('UTC',now())),date_trunc('second',timezone('UTC',now())))
      ON CONFLICT (environment,source,category,location) DO UPDATE SET
        occurrences=CASE WHEN i.last_seen < excluded.last_seen - interval '1 day' THEN excluded.occurrences ELSE i.occurrences + excluded.occurrences END,
        sent=CASE WHEN i.last_seen < excluded.last_seen - interval '1 day' THEN false ELSE i.sent END,
        attempts=CASE WHEN i.last_seen < excluded.last_seen - interval '1 day' THEN 0 ELSE i.attempts END,
        next_attempt=CASE WHEN i.last_seen < excluded.last_seen - interval '1 day' THEN excluded.last_seen ELSE i.next_attempt END,
        last_seen=excluded.last_seen,release=excluded.release,request_ref=coalesce(excluded.request_ref,i.request_ref)
      """,
      [environment(), source, category, location, release, count, ref && Ecto.UUID.dump!(ref)],
      log: false
    )
  end

  def prune do
    Repo.query!(
      "DELETE FROM operational_alert_attempts WHERE attempted_at < date_trunc('second',timezone('UTC',now())) - interval '1 day'",
      [],
      log: false
    )

    Repo.query!(
      "DELETE FROM operational_incidents WHERE last_seen < date_trunc('second',timezone('UTC',now())) - interval '30 days'",
      [],
      log: false
    )

    Repo.query!(
      """
      DELETE FROM operational_incidents WHERE id IN (
        SELECT id FROM (SELECT id,row_number() OVER (PARTITION BY environment,source ORDER BY last_seen DESC,id DESC) AS rank
        FROM operational_incidents) ranked WHERE rank > 512)
      """,
      [],
      log: false
    )
  end
end
