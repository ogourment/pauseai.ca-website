defmodule PauseAiCa.Newsletters.ProviderReconciliation do
  @moduledoc "Durable reconciliation of exact production receipts. Observations never grant consent or resend mail."
  import Ecto.Query
  alias PauseAiCa.{Repo, Newsletters}
  alias PauseAiCa.Newsletters.{Batch, Delivery, ProviderEvent, Subscription}

  @doc "Aggregate-only, read-only import preview. No source payloads or recipient addresses are returned."
  def preview(events) do
    with {:ok, plan} <- plan(events), do: {:ok, plan.counts}
  end

  def reconcile(events) do
    Repo.transaction(fn ->
      Ecto.Adapters.SQL.query!(
        Repo,
        "SELECT pg_advisory_xact_lock(hashtext('newsletter-provider-reconciliation'))",
        []
      )

      case plan(events) do
        {:ok, plan} ->
          Enum.each(plan.rows, &record/1)
          plan.counts

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc "Address-only delivery holds. A later delivery/open never clears a permanent failure."
  def address_suppressed?(email), do: MapSet.member?(suppressed_emails([email]), email)

  def suppressed_emails(emails) do
    Repo.all(
      from e in ProviderEvent,
        where:
          e.email in ^emails and
            (e.kind == "hard_bounce" or (e.kind == "review" and e.reason == "invalid_domain")),
        distinct: true,
        select: e.email
    )
    |> MapSet.new()
  end

  def hold_reasons(emails) do
    Repo.all(
      from e in ProviderEvent,
        where:
          e.email in ^emails and
            (e.kind == "hard_bounce" or (e.kind == "review" and e.reason == "invalid_domain")),
        select: {e.email, e.kind}
    )
    |> Enum.reduce(%{}, fn {email, kind}, acc ->
      if kind == "hard_bounce",
        do: Map.put(acc, email, :hard_bounce),
        else: Map.put_new(acc, email, :invalid_domain)
    end)
  end

  def summary(deliveries) do
    ids = Enum.map(deliveries, & &1.id)

    counts =
      Repo.all(
        from e in ProviderEvent,
          where: e.delivery_id in ^ids,
          group_by: e.kind,
          select: {e.kind, count(e.email, :distinct)}
      )
      |> Map.new()

    Map.merge(%{"hard_bounce" => 0, "unsubscribe" => 0, "review" => 0}, counts)
    |> Map.put(
      "conflicts",
      Repo.aggregate(
        from(e in ProviderEvent,
          where: e.delivery_id in ^ids and e.consent_conflict,
          distinct: e.email
        ),
        :count,
        :email
      )
    )
    |> Map.put(
      "invalid_domain",
      Repo.aggregate(
        from(e in ProviderEvent,
          where: e.delivery_id in ^ids and e.kind == "review" and e.reason == "invalid_domain",
          distinct: e.email
        ),
        :count,
        :email
      )
    )
  end

  def review_rows(deliveries) do
    ids = Enum.map(deliveries, & &1.id)

    Repo.all(
      from e in ProviderEvent,
        where: e.delivery_id in ^ids,
        order_by: [desc: e.occurred_at, desc: e.id],
        limit: 500
    )
    |> Enum.uniq_by(&{&1.delivery_id, &1.kind, &1.reason})
  end

  defp plan(events) when is_list(events) and length(events) <= 20_000 do
    {classified, ignored, invalid} =
      Enum.reduce(events, {[], 0, 0}, fn raw, {rows, ignored, invalid} ->
        case PhoenixMailWorkflow.ProviderEvents.classify(raw) do
          {:ok, event} -> {[event | rows], ignored, invalid}
          :ignore -> {rows, ignored + 1, invalid}
          {:error, _} -> {rows, ignored, invalid + 1}
        end
      end)

    unique = Enum.uniq_by(classified, & &1.key)
    ids = Enum.map(unique, & &1.provider_id)
    emails = Enum.map(unique, & &1.email)

    deliveries =
      Repo.all(
        from d in Delivery,
          join: b in Batch,
          on: b.id == d.batch_id,
          where:
            d.provider_id in ^ids and d.email in ^emails and not is_nil(d.attempted_at) and
              b.delivery_environment == "production",
          limit: 20_001
      )

    if length(deliveries) > 20_000 do
      {:error, :too_many_matches}
    else
      by_identity = Enum.group_by(deliveries, &{&1.provider_id, &1.email})

      matched =
        Enum.flat_map(unique, fn event ->
          case Map.get(by_identity, {event.provider_id, event.email}) do
            [delivery] -> [%{event: event, delivery: delivery}]
            _ -> []
          end
        end)

      keys = Enum.map(matched, & &1.event.key)

      existing =
        Repo.all(from e in ProviderEvent, where: e.event_key in ^keys, select: e.event_key)
        |> MapSet.new()

      rows = Enum.reject(matched, &MapSet.member?(existing, &1.event.key))

      counts = %{
        "matched" => length(matched),
        "unmatched" => length(unique) - length(matched),
        "ignored" => ignored,
        "invalid" => invalid,
        "duplicates" => length(classified) - length(unique),
        "already_recorded" => MapSet.size(existing),
        "new_events" => length(rows)
      }

      counts =
        Enum.reduce([:hard_bounce, :unsubscribe, :review], counts, fn kind, counts ->
          emails =
            rows
            |> Enum.filter(&(&1.event.kind == kind))
            |> Enum.map(& &1.event.email)
            |> Enum.uniq()

          Map.put(counts, Atom.to_string(kind), length(emails))
        end)

      invalid_domains =
        rows
        |> Enum.filter(&(&1.event.reason == :invalid_domain))
        |> Enum.map(& &1.event.email)
        |> Enum.uniq()
        |> length()

      counts = counts |> Map.put("invalid_domain", invalid_domains) |> withdrawal_preview(rows)
      {:ok, %{rows: rows, counts: counts}}
    end
  end

  defp plan(_), do: {:error, :invalid_events}

  defp withdrawal_preview(counts, rows) do
    events = rows |> Enum.filter(&(&1.event.kind == :unsubscribe)) |> Enum.map(& &1.event)
    emails = Enum.map(events, & &1.email)

    subscriptions =
      Repo.all(from s in Subscription, where: s.email in ^emails)
      |> Map.new(&{&1.email, &1})

    groups =
      Enum.group_by(events, fn event ->
        case subscriptions[event.email] do
          %{state: "withdrawn"} ->
            "already_withdrawn"

          nil ->
            "new_withdrawals"

          subscription ->
            if Enum.any?(
                 [subscription.confirmed_at, subscription.requested_at],
                 &(not is_nil(&1) and DateTime.compare(&1, event.occurred_at) == :gt)
               ), do: "consent_conflicts", else: "new_withdrawals"
        end
      end)

    Enum.reduce(["already_withdrawn", "new_withdrawals", "consent_conflicts"], counts, fn key,
                                                                                          acc ->
      recipients = Map.get(groups, key, []) |> Enum.map(& &1.email) |> Enum.uniq()
      Map.put(acc, key, length(recipients))
    end)
  end

  defp record(%{event: event, delivery: delivery}) do
    now = DateTime.utc_now()
    id = Ecto.UUID.generate()

    withdrawal =
      if event.kind == :unsubscribe do
        Newsletters.withdraw_provider(
          event.email,
          %{
            "provider" => "brevo",
            "provider_event_id" => id,
            "newsletter_delivery_id" => delivery.id,
            "provider_message_id" => event.provider_id,
            "observed_at" => DateTime.to_iso8601(event.occurred_at)
          },
          event.occurred_at
        )
      end

    Repo.insert!(%ProviderEvent{
      id: id,
      delivery_id: delivery.id,
      event_key: event.key,
      email: event.email,
      kind: Atom.to_string(event.kind),
      reason: Atom.to_string(event.reason),
      consent_conflict: withdrawal == :conflict,
      occurred_at: event.occurred_at,
      inserted_at: now
    })

    if event.kind != :unsubscribe do
      # Delivery failure/review evidence is separate from purpose consent.
      if subscription = Repo.get_by(Subscription, email: event.email) do
        Repo.insert!(%PauseAiCa.Newsletters.ConsentEvent{
          subscription_id: subscription.id,
          kind: "provider_delivery_observed",
          consent_version: subscription.consent_version,
          evidence: %{
            "provider" => "brevo",
            "provider_event_id" => id,
            "observed_at" => DateTime.to_iso8601(event.occurred_at),
            "kind" => Atom.to_string(event.kind),
            "reason" => Atom.to_string(event.reason)
          },
          inserted_at: now
        })
      end
    end
  end
end
