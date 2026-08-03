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
