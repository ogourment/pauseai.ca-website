defmodule PauseAiCa.Campaigns.ConfirmationsTest do
  use PauseAiCa.DataCase, async: true

  import Swoosh.TestAssertions

  alias PauseAiCa.Campaigns
  alias PauseAiCa.Campaigns.Confirmations
  alias PauseAiCa.Campaigns.PendingLetter
  alias PauseAiCa.Campaigns.Representative
  alias PauseAiCa.Repo

  setup do
    member = %Representative{
      name: "Steven Guilbeault",
      district: "Laurier—Sainte-Marie",
      email: "Steven.Guilbeault@parl.gc.ca"
    }

    letter = Campaigns.compose_letter([member], :en, %{name: "Camille Roy"})
    supporter = %{name: "Camille Roy", email: "camille@example.org"}

    %{letter: letter, supporter: supporter}
  end

  test "holding a letter sends nothing yet", %{letter: letter, supporter: supporter} do
    assert {:ok, _token, %PendingLetter{}} = Confirmations.hold(letter, supporter, "en")

    refute_email_sent()
  end

  test "only the hash of the token is stored", %{letter: letter, supporter: supporter} do
    {:ok, token, pending} = Confirmations.hold(letter, supporter, "en")

    refute pending.token == token
    assert {:ok, hashed} = PendingLetter.hash(token)
    assert pending.token == hashed
  end

  test "releasing sends the letter and forgets the sender", %{
    letter: letter,
    supporter: supporter
  } do
    {:ok, token, _pending} = Confirmations.hold(letter, supporter, "en")

    assert {:ok, %{locale: "en"}} = Confirmations.release(token)
    assert_email_sent(fn email -> email.reply_to == {"Camille Roy", "camille@example.org"} end)
    assert Repo.aggregate(PendingLetter, :count) == 0
  end

  test "the website's deduplicated pending letter releases its linked anonymous intent exactly once",
       %{
         letter: letter,
         supporter: supporter
       } do
    supporter = %{supporter | email: "linked-#{System.unique_integer([:positive])}@example.org"}
    assert {:ok, token, pending} = Confirmations.hold(letter, supporter, "en", [])
    assert is_binary(pending.send_intent_id)
    assert :ok = Confirmations.notify(pending, token, fn _, _ -> {:ok, %{}} end)
    assert {:ok, nil, reused} = Confirmations.hold(letter, supporter, "en", [])
    assert reused.id == pending.id
    assert reused.send_intent_id == pending.send_intent_id
    refute_email_sent()

    assert {:ok, %{locale: "en"}} = Confirmations.release(token)

    assert_email_sent(fn email ->
      email.reply_to == {supporter.name, supporter.email} and
        email.headers["IdempotencyKey"] == pending.send_intent_id
    end)

    assert {:error, :not_found} = Confirmations.release(token)
    refute_email_sent()
    assert Repo.get(PendingLetter, pending.id) == nil
    intent = Repo.get!(PauseAiCa.Campaigns.SendIntent, pending.send_intent_id)
    assert intent.state == "accepted"
    assert intent.actor_id == nil
    assert intent.action_id == nil
    assert Repo.aggregate(PauseAiCa.Engagement.Action, :count) == 0
  end

  test "an expired linked pending letter gets a fresh usable token on explicit retry", c do
    supporter = %{c.supporter | email: "expiry-#{System.unique_integer([:positive])}@example.org"}
    {:ok, old_token, pending} = Confirmations.hold(c.letter, supporter, "en", [])
    assert :ok = Confirmations.notify(pending, old_token, fn _, _ -> {:ok, %{}} end)

    pending
    |> Ecto.Changeset.change(
      expires_at: DateTime.add(DateTime.utc_now(), -3600) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:ok, token, renewed} = Confirmations.hold(c.letter, supporter, "en", [])
    assert is_binary(token)
    refute token == old_token
    assert renewed.id == pending.id
    assert renewed.send_intent_id == pending.send_intent_id
    assert renewed.body == pending.body
    assert {:error, :not_found} = Confirmations.release(old_token)
    assert {:ok, _} = Confirmations.release(token)
  end

  test "definite confirmation rejection can explicitly retry with one new token and the same reviewed letter",
       c do
    supporter = %{c.supporter | email: "retry-#{System.unique_integer([:positive])}@example.org"}
    {:ok, original_token, pending} = Confirmations.hold(c.letter, supporter, "en", [])

    assert {:error, :delivery_failed} =
             Confirmations.notify(pending, original_token, fn _, _ -> {:error, :rejected} end)

    assert {:ok, token, renewed} = Confirmations.hold(c.letter, supporter, "en", [])
    assert renewed.id == pending.id
    assert renewed.send_intent_id == pending.send_intent_id
    assert renewed.body == pending.body
    refute token == original_token
    assert {:error, :not_found} = Confirmations.release(original_token)

    assert :ok =
             Confirmations.notify(renewed, token, fn row, current_token ->
               PauseAiCa.Campaigns.ConfirmationNotifier.deliver(
                 row,
                 "https://example.org/confirm/#{current_token}"
               )
             end)

    assert_email_sent(fn email -> String.contains?(email.text_body, token) end)
    assert {:ok, nil, reused} = Confirmations.hold(c.letter, supporter, "en", [])

    assert :ok =
             Confirmations.notify(reused, nil, fn _, _ ->
               flunk("accepted notification must not resend")
             end)

    refute_email_sent()
    assert {:ok, _} = Confirmations.release(token)
  end

  test "an interrupted pre-notification hold can safely rotate before any email was attempted",
       c do
    supporter = %{
      c.supporter
      | email: "presend-#{System.unique_integer([:positive])}@example.org"
    }

    {:ok, old_token, pending} = Confirmations.hold(c.letter, supporter, "en", [])
    assert {:ok, token, renewed} = Confirmations.hold(c.letter, supporter, "en", [])
    assert renewed.id == pending.id
    refute token == old_token

    assert {:error, :not_found} =
             Confirmations.notify(pending, old_token, fn _, _ ->
               flunk("stale token cannot submit")
             end)

    assert :ok = Confirmations.notify(renewed, token, fn _, _ -> {:ok, %{}} end)
    refute_email_sent()
  end

  test "unknown or interrupted confirmation submission remains held even after token expiry", c do
    supporter = %{
      c.supporter
      | email: "unknown-#{System.unique_integer([:positive])}@example.org"
    }

    {:ok, token, pending} = Confirmations.hold(c.letter, supporter, "en", [])

    assert {:error, :delivery_unknown} =
             Confirmations.notify(pending, nil, fn _, _ ->
               flunk("a missing token cannot claim notification success")
             end)

    assert {:error, :delivery_unknown} =
             Confirmations.notify(pending, token, fn _, _ -> {:error, :timeout} end)

    assert {:error, :delivery_unknown} = Confirmations.hold(c.letter, supporter, "en", [])

    assert {:error, :delivery_unknown} =
             Confirmations.notify(pending, nil, fn _, _ -> flunk("unknown cannot resend") end)

    pending
    |> Ecto.Changeset.change(
      expires_at: DateTime.add(DateTime.utc_now(), -3600) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:error, :delivery_unknown} = Confirmations.hold(c.letter, supporter, "en", [])
    assert Repo.get!(PendingLetter, pending.id).token == pending.token
    refute_email_sent()
  end

  test "an MP outcome that becomes uncertain during notification is never overwritten or retried",
       c do
    supporter = %{
      c.supporter
      | email: "preserve-#{System.unique_integer([:positive])}@example.org"
    }

    {:ok, token, pending} = Confirmations.hold(c.letter, supporter, "en", [])

    assert :ok =
             Confirmations.notify(pending, token, fn row, _ ->
               intent = Repo.get!(PauseAiCa.Campaigns.SendIntent, row.send_intent_id)

               intent
               |> Ecto.Changeset.change(state: "unknown", error_code: "acceptance_unknown")
               |> Repo.update!()

               {:ok, %{}}
             end)

    intent = Repo.get!(PauseAiCa.Campaigns.SendIntent, pending.send_intent_id)
    assert intent.state == "unknown"
    assert intent.error_code == "acceptance_unknown"
    assert {:error, :delivery_unknown} = Confirmations.hold(c.letter, supporter, "en", [])
  end

  test "a token works once", %{letter: letter, supporter: supporter} do
    {:ok, token, _pending} = Confirmations.hold(letter, supporter, "en")

    assert {:ok, _result} = Confirmations.release(token)
    assert {:error, :not_found} = Confirmations.release(token)
  end

  test "an expired letter is never sent", %{letter: letter, supporter: supporter} do
    {:ok, token, pending} = Confirmations.hold(letter, supporter, "fr")

    pending
    |> Ecto.Changeset.change(
      expires_at: DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {:error, :not_found} = Confirmations.release(token)
    refute_email_sent()
  end

  test "a made-up token is refused without revealing anything" do
    assert {:error, :not_found} = Confirmations.release("not-a-real-token")

    assert {:error, :not_found} =
             Confirmations.release(Base.url_encode64("guess", padding: false))
  end

  test "sweeping removes expired letters and leaves live ones", %{
    letter: letter,
    supporter: supporter
  } do
    {:ok, _token, expired} = Confirmations.hold(letter, supporter, "en")
    {:ok, _token, _live} = Confirmations.hold(letter, supporter, "en")

    expired
    |> Ecto.Changeset.change(
      expires_at: DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
    )
    |> Repo.update!()

    assert {1, nil} = Confirmations.sweep()
    assert Repo.aggregate(PendingLetter, :count) == 1
  end

  test "the confirmation email teaches the recipient to rescue it from spam", %{
    letter: letter,
    supporter: supporter
  } do
    {:ok, token, pending} = Confirmations.hold(letter, supporter, "en")

    PauseAiCa.Campaigns.ConfirmationNotifier.deliver(
      pending,
      "https://pauseai.ca/letters/confirm/#{token}"
    )

    assert_email_sent(fn email ->
      assert email.html_body =~ "Not spam"
      assert email.html_body =~ "Non indésirable"
      assert email.text_body =~ "Not spam"
      # The instruction is the one thing we want acted on, so it is highlighted.
      assert email.html_body =~ "#fff8dc"
    end)
  end
end
