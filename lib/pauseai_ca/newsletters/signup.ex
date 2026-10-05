defmodule PauseAiCa.Newsletters.Signup do
  @moduledoc "Local opt-in followed by guarded confirmation delivery; provider failure never grants consent."
  import Ecto.Query
  alias PauseAiCa.{Newsletters, Repo, Mailer}
  alias PauseAiCa.Newsletters.{ConsentEvent, Subscription, Notifier}

  # Durable per-address cooldown, including failed/unknown delivery attempts.
  # A restart cannot turn repeated form submissions into a confirmation flood.
  @cooldown_seconds 60

  def request(email, attrs, url_builder, opts \\ []) when is_function(url_builder, 1) do
    case reserve(email, attrs, Keyword.get(opts, :admin_actor_id)) do
      {:ok, :unchanged} -> {:ok, :pending_confirmation}
      {:ok, request} -> deliver(request, url_builder, opts)
      error -> error
    end
  end

  defp reserve(email, attrs, actor_id) do
    normalized = if is_binary(email), do: email |> String.trim() |> String.downcase(), else: ""

    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "newsletter-signup:" <> normalized
      ])

      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "newsletter-confirmation-quota"
      ])

      cutoff = DateTime.add(DateTime.utc_now(), -@cooldown_seconds)
      hour = DateTime.add(DateTime.utc_now(), -3600)

      attempts =
        Repo.aggregate(
          from(e in ConsentEvent,
            where: e.kind == "confirmation_attempted" and e.inserted_at > ^hour
          ),
          :count
        )

      recent =
        Repo.exists?(
          from e in ConsentEvent,
            join: s in Subscription,
            on: s.id == e.subscription_id,
            where:
              s.email == ^normalized and e.kind == "confirmation_attempted" and
                e.inserted_at > ^cutoff
        )

      if attrs[:consent] != true, do: Repo.rollback(:consent_required)

      if recent do
        last_delivery =
          Repo.one(
            from e in ConsentEvent,
              join: s in Subscription,
              on: s.id == e.subscription_id,
              where: s.email == ^normalized and e.kind == "confirmation_delivery",
              order_by: [desc: e.inserted_at],
              limit: 1
          )

        if last_delivery && last_delivery.evidence["status"] == "failed",
          do: Repo.rollback(:confirmation_unavailable),
          else: :unchanged
      else
        if attempts >= 100, do: Repo.rollback(:confirmation_unavailable)

        case Newsletters.request_signup(email, attrs) do
          {:ok, %{confirmation_token: nil}} ->
            :unchanged

          {:ok, request} ->
            record(request.subscription, "confirmation_attempted", actor_id, %{})
            request

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end
    end)
  end

  defp deliver(request, url_builder, opts) do
    email = Notifier.confirmation(request.subscription, url_builder.(request.confirmation_token))
    result = Mailer.deliver(email, opts)
    status = if match?({:ok, _}, result), do: "accepted", else: "failed"

    record(request.subscription, "confirmation_delivery", Keyword.get(opts, :admin_actor_id), %{
      "status" => status
    })

    case result do
      {:ok, _} -> {:ok, :pending_confirmation}
      {:error, _} -> {:error, :confirmation_unavailable}
    end
  end

  defp record(subscription, kind, actor_id, evidence) do
    Repo.insert!(%ConsentEvent{
      subscription_id: subscription.id,
      kind: kind,
      actor_id: actor_id,
      consent_version: subscription.consent_version,
      evidence: evidence,
      inserted_at: DateTime.utc_now()
    })
  end
end
