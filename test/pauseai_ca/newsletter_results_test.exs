defmodule PauseAiCa.NewsletterResultsTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters}
  alias PauseAiCa.Newsletters.{Drafts, Batches, Delivery, Results, Batch}

  setup do
    admin = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(admin)
    {:ok, signup} = Newsletters.request_signup("results@example.org", %{consent: true})
    {:ok, _} = Newsletters.confirm(signup.confirmation_token)
    {:ok, draft} = Drafts.create(scope)

    {:ok, draft} =
      Drafts.save(scope, draft, %{
        "subject" => "Synthetic results",
        "source" => "News",
        "recipient_mode" => "newsletter",
        "recipient_keys" => [signup.subscription.id]
      })

    {:ok, batch} = Batches.prepare(scope, draft, "newsletter", [signup.subscription.id], true)
    delivery = Repo.get_by!(Delivery, batch_id: batch.id)
    %{scope: scope, batch: batch, delivery: delivery}
  end

  test "reports attempted sends only, attributes exact local withdrawal and enforces fresh authority",
       c do
    assert {:ok, []} = Results.list(c.scope)
    assert {:error, :unauthorized} = Results.get(c.scope, c.batch.id)

    c.delivery
    |> change(
      state: "accepted",
      attempted_at: DateTime.utc_now(),
      authorizing_admin_id: c.scope.user.id,
      provider_id: "test-message"
    )
    |> Repo.update!()

    assert {:ok, [%{id: id}]} = Results.list(c.scope)
    assert id == c.batch.id

    {:ok, raw} =
      Phoenix.Token.decrypt(
        PauseAiCaWeb.Endpoint,
        "newsletter delivery footer",
        c.delivery.withdrawal_token,
        max_age: :infinity
      )

    {:ok, _} = Newsletters.withdraw(raw)
    {:ok, _} = Newsletters.withdraw(raw)
    assert {:ok, %{local_unsubscribed: 1, report: %{total: 1}}} = Results.get(c.scope, id)
    c.scope.user |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Results.get(c.scope, id)
    assert {:error, :unauthorized} = Results.refresh(c.scope, id)
  end

  test "provider outcomes match frozen message IDs and recipient addresses; errors do not become zero",
       c do
    c.delivery
    |> change(
      state: "accepted",
      attempted_at: DateTime.utc_now(),
      authorizing_admin_id: c.scope.user.id,
      provider_id: "test-message"
    )
    |> Repo.update!()

    Repo.get!(Batch, c.batch.id) |> change(delivery_environment: "production") |> Repo.update!()
    old_key = Application.get_env(:pauseai_ca, :brevo_api_key)
    old_options = Application.get_env(:pauseai_ca, :brevo_history_req_options)

    on_exit(fn ->
      Application.put_env(:pauseai_ca, :brevo_api_key, old_key)

      if old_options,
        do: Application.put_env(:pauseai_ca, :brevo_history_req_options, old_options),
        else: Application.delete_env(:pauseai_ca, :brevo_history_req_options)
    end)

    Application.put_env(:pauseai_ca, :brevo_api_key, "synthetic")

    Application.put_env(:pauseai_ca, :brevo_history_req_options,
      plug: fn conn ->
        assert conn.request_path == "/v3/smtp/statistics/events"

        Req.Test.json(conn, %{
          "events" => [
            %{
              "messageId" => "test-message",
              "email" => "results@example.org",
              "event" => "delivered"
            },
            %{"messageId" => "other", "email" => "results@example.org", "event" => "opened"}
          ]
        })
      end
    )

    assert {:ok, %{report: report, partial: false}} = Results.refresh(c.scope, c.batch.id)
    assert report.observed.delivered == 1
    assert report.observed.opened == 0

    Application.put_env(:pauseai_ca, :brevo_history_req_options,
      plug: fn conn -> Plug.Conn.send_resp(conn, 429, "") end
    )

    assert {:error, :rate_limited} = Results.refresh(c.scope, c.batch.id)
  end
end
