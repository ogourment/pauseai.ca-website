defmodule PauseAiCa.AuditTest do
  @moduledoc """
  Logs are the easiest place to leak supporter data by accident, so what this
  module refuses to write matters as much as what it writes.
  """

  # Not async: the Logger level is global and this raises it.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias PauseAiCa.Audit

  setup do
    # Audit events are :info; the test env floor is :warning.
    previous = Logger.level()
    Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: previous) end)
    :ok
  end

  test "records the event and its safe metadata" do
    log = capture_log(fn -> Audit.event(:letter_sent, %{locale: "fr", verified: true}) end)

    assert log =~ "pauseai.letter_sent"
    assert log =~ ~s(locale="fr")
    assert log =~ "verified=true"
  end

  test "an email never reaches the log" do
    log = capture_log(fn -> Audit.event(:letter_sent, %{email: "camille@example.org"}) end)

    refute log =~ "camille@example.org"
    refute log =~ "example.org"
    assert log =~ "actor="
  end

  test "the same person is recognisable across events without being identified" do
    first = Audit.actor("Camille@Example.org")
    second = Audit.actor("  camille@example.org  ")

    assert first == second
    refute first =~ "camille"
    assert String.length(first) == 12
  end

  test "postal codes, letter bodies and names are dropped" do
    log =
      capture_log(fn ->
        Audit.event(:letter_sent, %{
          postal_code: "H2X 1Y4",
          body: "the whole letter",
          name: "Camille Roy",
          recipients: "Steven.Guilbeault@parl.gc.ca",
          locale: "en"
        })
      end)

    refute log =~ "H2X"
    refute log =~ "the whole letter"
    refute log =~ "Camille Roy"
    refute log =~ "parl.gc.ca"
    assert log =~ ~s(locale="en")
  end

  test "an anonymous actor is named as such rather than left blank" do
    assert Audit.actor(nil) == "anonymous"
  end
end
