defmodule PauseAiCaWeb.LetterControllerTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Swoosh.TestAssertions
  alias PauseAiCa.Campaigns.{Confirmations, Letter, PendingLetter, SendIntent}
  alias PauseAiCa.Repo

  test "a valid token with held delivery shows its operator reference without claiming expiry", %{
    conn: conn
  } do
    letter = %Letter{
      to: "mp@example.org",
      subject: "Reviewed request",
      body: "Please support effective oversight. Thank you."
    }

    supporter = %{
      name: "Camille",
      email: "held-#{System.unique_integer([:positive])}@example.org"
    }

    {:ok, token, pending} = Confirmations.hold(letter, supporter, "en", [])
    intent = Repo.get!(SendIntent, pending.send_intent_id)

    intent
    |> Ecto.Changeset.change(state: "unknown", error_code: "acceptance_unknown")
    |> Repo.update!()

    response = get(conn, "/letters/confirm/#{token}")
    assert redirected_to(response) == "/en/contact-your-mp"
    message = Phoenix.Flash.get(response.assigns.flash, :error)
    assert message =~ "Delivery is awaiting verification"
    assert message =~ pending.send_intent_id
    refute message =~ "no longer valid"
    assert Repo.get!(PendingLetter, pending.id).body == letter.body
    assert Repo.get!(SendIntent, intent.id).state == "unknown"
    refute_email_sent()
  end

  test "a held French letter keeps French outcome language and redirect on the unprefixed token route",
       %{conn: conn} do
    letter = %Letter{
      to: "mp@example.org",
      subject: "Demande révisée",
      body: "Veuillez soutenir une surveillance efficace. Merci."
    }

    supporter = %{
      name: "Camille",
      email: "fr-held-#{System.unique_integer([:positive])}@example.org"
    }

    {:ok, token, pending} = Confirmations.hold(letter, supporter, "fr", [])
    intent = Repo.get!(SendIntent, pending.send_intent_id)

    intent
    |> Ecto.Changeset.change(state: "unknown", error_code: "acceptance_unknown")
    |> Repo.update!()

    response = get(conn, "/letters/confirm/#{token}")
    assert redirected_to(response) == "/fr/contacter-votre-depute"
    message = Phoenix.Flash.get(response.assigns.flash, :error)
    assert message =~ "L’envoi doit être vérifié"
    assert message =~ pending.send_intent_id
    assert Confirmations.context(token).locale == "fr"
    refute_email_sent()
  end
end
