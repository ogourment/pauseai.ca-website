defmodule PauseAiCa.Assistant.SpendTrackingTest do
  use PauseAiCa.DataCase, async: false
  import Ecto.Query
  alias PauseAiCa.{Assistant, AssistantFixtures, Repo}
  alias PauseAiCa.Assistant.SpendTracking
  alias PhoenixAgentAssistant.{Canonical, SpendLedger, Store}
  alias PhoenixAgentAssistant.Store.{Request, SpendEntry}

  # Synthetic anchoring fixture only; this does not prove a real receiver receipt.
  defmodule Operations do
    def confirm(entry, options) do
      number = Agent.get_and_update(options[:counter], fn n -> {n + 1, n + 1} end)
      send(options[:owner], {:spend_anchor, entry.id})
      if number == options[:fail_at], do: {:error, :fixture_anchor_unavailable}, else: :ok
    end
  end

  setup do
    counter = start_supervised!({Agent, fn -> 0 end})

    config =
      AssistantFixtures.configuration()
      |> Keyword.put(:stage_tracking, :required)
      |> Keyword.put(:provider, {PhoenixAgentAssistant.OpenAI, [api_key: "SYNTHETIC-NOT-USED"]})
      |> Keyword.put(:safety,
        moderation:
          {PhoenixAgentAssistant.Safety.OpenAIModeration, [model: "moderation-fixture"]},
        jev: {PhoenixAgentAssistant.Safety.Jev, [model: "jev-fixture"]}
      )
      |> Keyword.put(:operations_adapter, {Operations, [owner: self(), counter: counter]})

    actor = "synthetic-spend-" <> Ecto.UUID.generate()
    store = Assistant.store()

    assert {:ok, _} =
             Store.set_enabled(store, actor, true, Ecto.UUID.generate(), config[:audit_keys])

    reservation = %{
      request_id: Ecto.UUID.generate(),
      digest: String.duplicate("a", 64),
      mode: "fast",
      model: "haiku-fixture",
      max_output_tokens: config[:max_output_tokens],
      max_tokens: 4096,
      max_cost_micros: config[:max_turn_cost_micros]
    }

    %{store: store, actor: actor, config: config, reservation: reservation, counter: counter}
  end

  defp anchors(acc \\ []) do
    receive do
      {:spend_anchor, id} -> anchors(acc ++ [id])
    after
      0 -> acc
    end
  end

  test "five slots share model/rate snapshot and entire maximum, with explicit free moderation",
       c do
    assert {:ok, slots} = SpendTracking.slots(c.reservation, c.config)

    assert Enum.map(slots, & &1["purpose"]) ==
             ~w(generation input_moderation input_jev output_moderation output_jev)

    assert Enum.sum(Enum.map(slots, & &1["max_cost_micros"])) == c.reservation.max_cost_micros
    assert hd(slots)["provider"] == "openai"
    assert hd(slots)["model"] == c.reservation.model
    assert hd(slots)["max_cost_micros"] == 998

    for slot <- slots do
      assert slot["rate_policy_id"] == c.config[:pricing]["policy_id"]

      if slot["purpose"] in ~w(input_moderation output_moderation) do
        assert slot["model"] == "moderation-fixture"

        assert slot["max_cost_micros"] == 0 and slot["input_micros"] == 0 and
                 slot["output_micros"] == 0
      end
    end
  end

  test "changed model maximum missing reviewer or invalid price policy cannot produce a plan",
       c do
    for {reservation, config} <- [
          {Map.put(c.reservation, :model, "different-model"), c.config},
          {Map.put(c.reservation, :max_cost_micros, 999), c.config},
          {Map.put(c.reservation, :max_output_tokens, 1), c.config},
          {c.reservation, Keyword.put(c.config, :safety, [])},
          {c.reservation, Keyword.delete(c.config, :pricing)},
          {c.reservation, Keyword.put(c.config, :stage_tracking, :disabled)}
        ] do
      assert {:error, :invalid_spend_plan} = SpendTracking.slots(reservation, config)
    end
  end

  test "reservation and each of five committed plan audit IDs are anchored before success", c do
    assert {:ok, ticket} = SpendTracking.reserve(c.store, c.actor, c.reservation, c.config)

    rows =
      Repo.all(from e in SpendEntry, where: e.request_id == ^ticket.id, order_by: e.inserted_at)

    assert length(rows) == 5
    [request_ref | plan_refs] = anchors()
    assert request_ref == ticket.audit_ref

    assert length(plan_refs) == 5 and
             MapSet.new(plan_refs) == MapSet.new(Enum.map(rows, & &1.audit_ref))

    assert {:ok, summary} =
             SpendLedger.summary(c.store, c.actor, Date.utc_today(), c.config[:audit_keys])

    assert summary.unresolved_stage_hold_micros == c.reservation.max_cost_micros
  end

  test "partial plan anchoring failure retains the request and all five conservative holds", c do
    config =
      Keyword.put(
        c.config,
        :operations_adapter,
        {Operations, [owner: self(), counter: c.counter, fail_at: 2]}
      )

    assert {:error, :audit_anchor_unavailable} =
             SpendTracking.reserve(c.store, c.actor, c.reservation, config)

    ticket = Repo.one!(from r in Request, where: r.actor_id == ^c.actor)
    assert ticket.state == "reserved" and ticket.max_cost_micros == c.reservation.max_cost_micros
    assert Repo.aggregate(from(e in SpendEntry, where: e.request_id == ^ticket.id), :count) == 5

    assert {:ok, summary} =
             SpendLedger.summary(c.store, c.actor, Date.utc_today(), c.config[:audit_keys])

    assert summary.unresolved_stage_hold_micros == c.reservation.max_cost_micros
  end

  test "stage event evidence is deterministic and replay anchors the original exact row", c do
    assert {:ok, ticket} = SpendTracking.reserve(c.store, c.actor, c.reservation, c.config)
    anchors()
    started = %{"state" => "started", "usage" => nil, "billing" => nil}
    assert :ok = SpendTracking.observe(c.store, c.actor, ticket, "generation", started, c.config)
    [started_ref] = anchors()

    reported = %{
      "state" => "reported",
      "usage" => %{"input_tokens" => 3, "output_tokens" => 4},
      "billing" => nil
    }

    assert :ok = SpendTracking.observe(c.store, c.actor, ticket, "generation", reported, c.config)
    [_reported_ref] = anchors()
    assert :ok = SpendTracking.observe(c.store, c.actor, ticket, "generation", started, c.config)
    assert anchors() == [started_ref]

    row =
      Repo.one!(
        from e in SpendEntry,
          where: e.request_id == ^ticket.id and e.purpose == "generation" and e.revision == 2
      )

    assert row.payload["observation"]["evidence_ref"] ==
             Canonical.digest(%{
               "request" => ticket.id,
               "purpose" => "generation",
               "event" => started
             })

    assert Repo.aggregate(
             from(e in SpendEntry,
               where: e.request_id == ^ticket.id and e.purpose == "generation"
             ),
             :count
           ) == 3
  end

  test "extra event fields or wrong actor fail before an observation or anchor", c do
    assert {:ok, ticket} = SpendTracking.reserve(c.store, c.actor, c.reservation, c.config)
    anchors()
    event = %{"state" => "started", "usage" => nil, "billing" => nil}

    assert {:error, _} =
             SpendTracking.observe(
               c.store,
               c.actor,
               ticket,
               "generation",
               Map.put(event, "plaintext", "forbidden"),
               c.config
             )

    assert {:error, _} =
             SpendTracking.observe(
               c.store,
               "different-actor",
               ticket,
               "generation",
               event,
               c.config
             )

    assert anchors() == []
    assert Repo.aggregate(from(e in SpendEntry, where: e.request_id == ^ticket.id), :count) == 5
  end
end
