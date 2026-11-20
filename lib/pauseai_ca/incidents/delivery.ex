defmodule PauseAiCa.Incidents.Delivery do
  alias PauseAiCa.{Incidents, Repo}

  def dispatch(send_message) do
    case reserve(Incidents.environment()) do
      {:ok, [id, category, source, location, release, count, ref, attempt]} ->
        action =
          case source do
            "mail" ->
              "Confirmation was not dispatched. Inspect the participation request and mail routing before retrying."

            "browser" ->
              "A browser operation failed. Check this release and reproduce the affected screen."

            "server" ->
              "A server operation failed. Inspect application logs for this location and release."
          end

        message =
          "#{Incidents.environment()} · PauseAI #{release} · incident #{id}\n#{source}: #{category} at #{location} (#{count} occurrences)\n#{action}" <>
            if(ref, do: "\nRequest: #{ref}", else: "")

        result = send_message.(message)
        # Fence stale acknowledgements from an earlier attempt.
        Repo.query!(
          "UPDATE operational_incidents SET sent=$3 WHERE id=$1 AND attempts=$2",
          [id, attempt, result == :ok],
          log: false
        )

        result

      {:ok, nil} ->
        :idle

      error ->
        error
    end
  end

  defp reserve(env) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", ["ops-alert:" <> env],
        log: false
      )

      %{rows: [[used]]} =
        Repo.query!(
          "SELECT count(*) FROM operational_alert_attempts WHERE environment=$1 AND attempted_at > date_trunc('second',timezone('UTC',now())) - interval '10 minutes'",
          [env],
          log: false
        )

      if used < 3 do
        result =
          Repo.query!(
            """
            UPDATE operational_incidents SET attempts=attempts+1,
              next_attempt=date_trunc('second',timezone('UTC',now())) + interval '2 minutes' * power(2,attempts)
            WHERE id=(SELECT id FROM operational_incidents WHERE environment=$1 AND NOT sent
              AND last_seen >= timezone('UTC',now()) - interval '1 day' AND attempts < 5 AND next_attempt <= date_trunc('second',timezone('UTC',now()))
              ORDER BY CASE source WHEN 'mail' THEN 0 WHEN 'server' THEN 1 ELSE 2 END,next_attempt,id LIMIT 1 FOR UPDATE)
            RETURNING id,category,source,location,release,occurrences,request_ref::text,attempts
            """,
            [env],
            log: false
          )

        case result.rows do
          [row] ->
            Repo.query!(
              "INSERT INTO operational_alert_attempts(environment,attempted_at) VALUES($1,date_trunc('second',timezone('UTC',now())))",
              [env],
              log: false
            )

            row

          [] ->
            nil
        end
      end
    end)
  end

  def telegram(token, chat_id, text, http_post \\ &Req.post/2) do
    case http_post.("https://api.telegram.org/bot#{token}/sendMessage",
           json: %{chat_id: chat_id, text: text},
           retry: false,
           redirect: false,
           receive_timeout: 5_000,
           connect_options: [timeout: 5_000]
         ) do
      {:ok, %{status: 200, body: %{"ok" => true}}} -> :ok
      _ -> :failed
    end
  end
end
