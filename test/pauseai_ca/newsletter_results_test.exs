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
    assert Results.recipient_counts(c.scope, [id])[id] == 1

    assert Results.recipient_summaries(c.scope, [id])[id] == %{
             count: 1,
             emails: ["results@example.org"]
           }

    assert [%{id: actor, email: email}] = Results.senders(c.scope, [id])[id]
    assert actor == c.scope.user.id
    assert email == c.scope.user.email
    {:ok, contact} = PauseAiCa.CRM.create(c.scope, %{email: "results@example.org"})
    assert {:ok, [%{admin_email: ^email}]} = Results.contact_history(c.scope, contact.person.id)
    # Pausing clears approver_id, but the actual authorizing actor survives on the delivery.
    Repo.get!(Batch, id) |> change(approver_id: nil) |> Repo.update!()
    assert [%{id: ^actor}] = Results.senders(c.scope, [id])[id]

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
            %{
              "messageId" => "test-message",
              "email" => "results@example.org",
              "event" => "loadedByProxy"
            },
            %{
              "messageId" => "test-message",
              "email" => "results@example.org",
              "event" => "loadedByProxy"
            },
            %{"messageId" => "other", "email" => "results@example.org", "event" => "opened"}
          ]
        })
      end
    )

    assert {:ok, %{report: report, partial: false}} = Results.refresh(c.scope, c.batch.id)
    assert report.observed.delivered == 1
    assert report.observed.opened == 0
    assert report.observed.proxy_opened == 1

    assert {:ok, %{provider: %{report: stored, refreshed_at: at}}} =
             Results.get(c.scope, c.batch.id)

    assert stored.observed.delivered == 1
    assert stored.observed.proxy_opened == 1
    assert %DateTime{} = at

    Application.put_env(:pauseai_ca, :brevo_history_req_options,
      plug: fn conn -> Plug.Conn.send_resp(conn, 429, "") end
    )

    assert {:error, :rate_limited} = Results.refresh(c.scope, c.batch.id)

    assert {:ok, %{provider: %{report: retained, refreshed_at: ^at}}} =
             Results.get(c.scope, c.batch.id)

    assert retained.observed.delivered == 1
  end

  test "complete reports include matching events beyond the worker's 2000-row budget", c do
    accepted_production_receipt(c)
    parent = self()

    filler = %{
      "messageId" => "unrelated-message",
      "email" => "other@example.org",
      "event" => "opened"
    }

    observed = %{
      "messageId" => "test-message",
      "email" => "results@example.org",
      "event" => "delivered"
    }

    events = List.duplicate(filler, 5_000) ++ [observed, Map.put(observed, "event", "opened")]

    stub_report(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.params["limit"] == "5000"
      offset = String.to_integer(conn.params["offset"])
      send(parent, {:report_offset, offset})
      Req.Test.json(conn, %{"events" => Enum.slice(events, offset, 5_000)})
    end)

    assert {:ok, %{report: report, partial: false}} = Results.refresh(c.scope, c.batch.id)
    assert report.observed.delivered == 1
    assert report.observed.opened == 1
    assert_receive {:report_offset, 0}
    assert_receive {:report_offset, 5_000}
    refute_receive {:report_offset, _}
    assert {:ok, %{provider: %{report: saved, partial: false}}} = Results.get(c.scope, c.batch.id)
    assert saved.observed.delivered == 1
    assert saved.observed.opened == 1
  end

  test "an exhausted report budget preserves complete cached counts and their original timestamp",
       c do
    accepted_production_receipt(c)
    at = DateTime.add(DateTime.utc_now(), -900)

    Repo.insert!(%PauseAiCa.Newsletters.ResultSnapshot{
      batch_id: c.batch.id,
      observed: %{"delivered" => 1, "opened" => 1},
      partial: false,
      refreshed_at: at
    })

    parent = self()

    filler = %{
      "messageId" => "unrelated-message",
      "email" => "other@example.org",
      "event" => "opened"
    }

    stub_report(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.params["limit"] == "5000"
      send(parent, {:report_offset, String.to_integer(conn.params["offset"])})
      Req.Test.json(conn, %{"events" => List.duplicate(filler, 5_000)})
    end)

    assert {:error, :incomplete_history} = Results.refresh(c.scope, c.batch.id)
    for offset <- [0, 5_000, 10_000, 15_000], do: assert_receive({:report_offset, ^offset})
    refute_receive {:report_offset, _}

    assert {:ok, %{provider: %{report: retained, partial: false, refreshed_at: ^at}}} =
             Results.get(c.scope, c.batch.id)

    assert retained.observed.delivered == 1
    assert retained.observed.opened == 1
  end

  test "link reports retain safe authored destinations and unique matched clicks only", c do
    accepted_production_receipt(c)

    source = """
    [**Toronto** waitlist](https://example.org/en/participate?intent=waitlist&city=Toronto)
    [Montréal waitlist](https://example.org/en/participate?intent=waitlist&city=Montreal)
    [Unread story](https://example.org/story)
    [Duplicate](https://example.org/en/participate?intent=waitlist&city=Toronto)
    [Withdraw](https://example.org/newsletters/withdraw?token=private-token)
    [Login](https://example.org/users/log-in/private-token)
    [Secret](https://example.org/story?key=private-key)
    [Personal](https://example.org/story?email=results%40example.org)
    [Placeholder](https://example.org/story?ref=%7B%7Brecipient%7D%7D)
    <a href="https://example.org/raw">Escaped HTML</a>
    """

    Repo.get!(Batch, c.batch.id) |> change(source: source) |> Repo.update!()

    click = %{
      "messageId" => "test-message",
      "email" => "results@example.org",
      "event" => "clicks",
      "link" => "https://example.org/en/participate?intent=waitlist&city=Toronto"
    }

    unsafe = [
      "https://example.org/newsletters/withdraw?token=private-token",
      "https://example.org/users/log-in/private-token",
      "https://example.org/story?key=private-key",
      "https://example.org/story?email=results%40example.org",
      "https://example.org/story?ref=%7B%7Brecipient%7D%7D",
      "https://example.org/raw",
      "https://example.org/not-authored"
    ]

    events =
      [
        click,
        click,
        Map.put(click, "email", "RESULTS@example.org"),
        Map.put(click, "messageId", "unrelated"),
        Map.put(click, "email", "other@example.org"),
        Map.put(click, "email", 42)
      ] ++ Enum.map(unsafe, &Map.put(click, "link", &1))

    stub_report(fn conn -> Req.Test.json(conn, %{"events" => events}) end)
    assert {:ok, %{links: links}} = Results.refresh(c.scope, c.batch.id)
    assert links["version"] == 1
    assert links["complete"]

    assert links["items"] == [
             %{
               "url" => "https://example.org/en/participate?intent=waitlist&city=Toronto",
               "label" => "Toronto waitlist",
               "clicked" => 1
             },
             %{
               "url" => "https://example.org/en/participate?intent=waitlist&city=Montreal",
               "label" => "Montréal waitlist",
               "clicked" => 0
             },
             %{"url" => "https://example.org/story", "label" => "Unread story", "clicked" => 0}
           ]

    assert {:ok, %{provider: %{links: ^links}}} = Results.get(c.scope, c.batch.id)

    stored =
      Repo.get!(PauseAiCa.Newsletters.ResultSnapshot, c.batch.id).observed["links"]
      |> Jason.encode!()

    for private <- [
          "results@example.org",
          "test-message",
          "private-token",
          "private-key",
          "recipient",
          "not-authored"
        ] do
      refute stored =~ private
    end
  end

  test "old cached reports are unavailable while complete empty link reports remain known", c do
    accepted_production_receipt(c)

    Repo.insert!(%PauseAiCa.Newsletters.ResultSnapshot{
      batch_id: c.batch.id,
      observed: %{"clicked" => 0},
      partial: false,
      refreshed_at: DateTime.utc_now()
    })

    assert {:ok, %{provider: %{links: nil}}} = Results.get(c.scope, c.batch.id)
    stub_report(fn conn -> Req.Test.json(conn, %{"events" => []}) end)

    assert {:ok, %{links: %{"version" => 1, "complete" => true, "items" => []}}} =
             Results.refresh(c.scope, c.batch.id)
  end

  defp accepted_production_receipt(c) do
    c.delivery
    |> change(
      state: "accepted",
      attempted_at: DateTime.utc_now(),
      authorizing_admin_id: c.scope.user.id,
      provider_id: "test-message"
    )
    |> Repo.update!()

    Repo.get!(Batch, c.batch.id) |> change(delivery_environment: "production") |> Repo.update!()
  end

  defp stub_report(plug) do
    previous =
      Map.new(
        [:brevo_api_key, :brevo_history_req_options],
        &{&1, Application.get_env(:pauseai_ca, &1)}
      )

    on_exit(fn ->
      Enum.each(previous, fn {key, value} ->
        if is_nil(value),
          do: Application.delete_env(:pauseai_ca, key),
          else: Application.put_env(:pauseai_ca, key, value)
      end)
    end)

    Application.put_env(:pauseai_ca, :brevo_api_key, "synthetic")
    Application.put_env(:pauseai_ca, :brevo_history_req_options, plug: plug)
  end
end
