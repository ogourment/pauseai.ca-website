defmodule PauseAiCa.ProviderReconciliationFixtures do
  @moduledoc "Five synthetic provider cases plus a local withdrawal baseline for isolated reconciliation acceptance checks."
  alias PauseAiCa.{Newsletters, Repo}
  alias PauseAiCa.Newsletters.{Batch, Delivery, Draft, ResultSnapshot, Subscription}
  @batch_id "ab000000-0000-4000-8000-000000000001"

  def five_receipts(scope) do
    now = DateTime.utc_now()

    draft =
      Repo.insert!(%Draft{
        owner_id: scope.user.id,
        subject: "Synthetic five-provider-case review"
      })

    recipients =
      Enum.map(["hard", "unsubscribe", "dns", "rbl", "full", "local"], fn label ->
        subscription =
          Repo.insert!(%Subscription{
            email: "#{label}@example.org",
            name: "Synthetic #{label}",
            state: "confirmed",
            locale: "en",
            consent_version: "synthetic-review",
            requested_at: DateTime.add(now, -7200),
            confirmed_at: DateTime.add(now, -7000)
          })

        {label, subscription}
      end)
      |> Map.new()

    batch =
      Repo.insert!(%Batch{
        id: @batch_id,
        draft_id: draft.id,
        owner_id: scope.user.id,
        draft_revision: 1,
        recipient_mode: "newsletter",
        recipient_keys: Enum.map(recipients, fn {_, s} -> s.id end),
        state: "completed",
        sender_name: "Synthetic review",
        sender_email: "sender@example.org",
        delivery_environment: "production",
        subject: "Synthetic five-provider-case review",
        source: "Synthetic receipt fixture; no messages sent.",
        preparation_key: :crypto.hash(:sha256, "synthetic-provider-reconciliation"),
        audience_digest: :crypto.hash(:sha256, "five-provider-cases-plus-local-baseline"),
        reviewed_at: now
      })

    tokens =
      Enum.map(recipients, fn {label, subscription} ->
        {:ok, token} = Newsletters.issue_withdrawal_token(scope, subscription.id)

        Repo.insert!(%Delivery{
          batch_id: batch.id,
          authorizing_admin_id: scope.user.id,
          recipient_key: subscription.id,
          email: subscription.email,
          withdrawal_token:
            Phoenix.Token.encrypt(PauseAiCaWeb.Endpoint, "newsletter delivery footer", token),
          state: "accepted",
          attempted_at: DateTime.add(now, -3600),
          accepted_at: DateTime.add(now, -3500),
          provider_id: "synthetic-#{label}"
        })

        {label, token}
      end)
      |> Map.new()

    {:ok, _} = Newsletters.withdraw(tokens["local"])

    Repo.insert!(%ResultSnapshot{
      batch_id: batch.id,
      observed: %{},
      partial: false,
      refreshed_at: now
    })

    events =
      Enum.map(
        [
          {"hard", "hardBounces", "Synthetic permanent failure"},
          {"unsubscribe", "unsubscribed", ""},
          {"dns", "softBounces", "Unable to find MX of domain example.invalid"},
          {"rbl", "softBounces", "Sender IP on Spamhaus RBL"},
          {"full", "softBounces", "Mailbox full"}
        ],
        fn {label, type, reason} ->
          %{
            "messageId" => "synthetic-#{label}",
            "email" => recipients[label].email,
            "event" => type,
            "date" => DateTime.to_iso8601(DateTime.add(now, -1800)),
            "reason" => reason
          }
        end
      )

    %{batch: batch, recipients: recipients, events: events, now: now}
  end

  def stub_history(events) do
    Application.put_env(:pauseai_ca, :brevo_api_key, "synthetic-provider-key")

    Application.put_env(:pauseai_ca, :brevo_history_req_options,
      plug: fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"events" => events}))
      end
    )
  end
end
