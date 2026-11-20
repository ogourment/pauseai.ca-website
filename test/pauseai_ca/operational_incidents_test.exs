defmodule PauseAiCa.OperationalIncidentsTest do
  use PauseAiCa.DataCase, async: false
  alias PauseAiCa.{Incidents, Repo}
  alias PauseAiCa.Incidents.{Delivery, Worker}

  setup do
    :ets.delete_all_objects(:pauseai_incident_buffer)
    :ok
  end

  defp browser(line) do
    Incidents.browser(%{
      "kind" => "exception",
      "class" => "TypeError",
      "surface" => "groups",
      "line" => line,
      "message" => "private@example.org"
    })
  end

  test "multiple visitors become one incident and only one notice" do
    for _ <- 1..200, do: browser(10)
    Incidents.flush()

    notify = fn message ->
      send(self(), {:alert, message})
      :ok
    end

    assert :ok = Delivery.dispatch(notify)
    assert_receive {:alert, message}
    assert message =~ "200 occurrences"
    refute message =~ "private@example.org"
    browser(10)
    Incidents.flush()
    assert :idle = Delivery.dispatch(notify)
    assert %{rows: [[201]]} = Repo.query!("select occurrences from operational_incidents")
  end

  test "all fingerprints share the environment delivery budget, including failed sends" do
    for line <- 1..8, do: browser(line)
    Incidents.flush()
    for _ <- 1..3, do: assert(:failed = Delivery.dispatch(fn _ -> :failed end))
    assert :idle = Delivery.dispatch(fn _ -> flunk("over budget") end)
    assert %{rows: [[3]]} = Repo.query!("select count(*) from operational_alert_attempts")

    Repo.query!(
      "update operational_alert_attempts set attempted_at=attempted_at - interval '1 hour'"
    )

    Repo.query!(
      "update operational_incidents set next_attempt=now() - interval '1 hour' where attempts=1"
    )

    assert :ok = Delivery.dispatch(fn _ -> :ok end)
  end

  test "a handled dispatch failure and a server exception are distinct and redact input" do
    id = Ecto.UUID.generate()
    Incidents.confirmation(:recipient_delivery_hold, id)
    Incidents.confirmation(:staging_admin_required, id)

    Worker.exception(
      [],
      %{},
      %{
        reason: RuntimeError.exception("private@example.org"),
        stacktrace: [{PauseAiCa.Participation, :request, ["sensitive"], []}]
      },
      nil
    )

    Incidents.flush()

    assert %{rows: [["mail", "staging_actor_required", ^id], ["server", "RuntimeError", nil]]} =
             Repo.query!(
               "select source,category,request_ref::text from operational_incidents order by source"
             )

    assert :ok =
             Delivery.dispatch(fn text ->
               assert text =~ id
               refute text =~ "sensitive"
               :ok
             end)
  end

  test "direct Telegram transport validates the response and never follows redirects" do
    http = fn url, options ->
      assert url == "https://api.telegram.org/botdemo/sendMessage"
      assert options[:json] == %{chat_id: "test-chat", text: "synthetic alert"}
      assert options[:redirect] == false
      assert options[:retry] == false
      {:ok, %{status: 200, body: %{"ok" => true}}}
    end

    assert :ok = Delivery.telegram("demo", "test-chat", "synthetic alert", http)

    assert :failed =
             Delivery.telegram("demo", "test-chat", "x", fn _, _ -> {:ok, %{status: 429}} end)
  end

  test "OTP error logger records a code location without message contents" do
    require Logger
    handler = :ops_error_test_handler
    :ok = :logger.add_handler(handler, PauseAiCa.Incidents.LogHandler, %{level: :error})

    try do
      ExUnit.CaptureLog.capture_log(fn -> Logger.error("sensitive diagnostic") end)
    after
      :logger.remove_handler(handler)
    end

    Incidents.flush()

    assert %{rows: [[location]]} =
             Repo.query!(
               "select location from operational_incidents where category='logged_error'"
             )

    assert location =~ "OperationalIncidentsTest"
    refute location =~ "sensitive"
  end
end
