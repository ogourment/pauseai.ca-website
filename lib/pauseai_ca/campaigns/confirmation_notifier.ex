defmodule PauseAiCa.Campaigns.ConfirmationNotifier do
  @moduledoc """
  Asks an unverified sender to release their own letter.

  Carries the spam-folder guidance, because this is the first message most
  people will ever receive from this domain and it is the moment where their
  "not spam" is worth the most.
  """

  import Swoosh.Email

  alias PauseAiCa.Campaigns.PendingLetter
  alias PauseAiCa.Mailer
  alias PauseAiCaWeb.Emails.Layout

  @default_sender {"PauseAI Canada", "info@pauseai.ca"}

  @doc """
  Emails `pending`'s sender the link that releases their letter.
  """
  @spec deliver(PendingLetter.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def deliver(%PendingLetter{} = pending, url) do
    {html, text} =
      Layout.render(
        "One click and your letter goes",
        "Un clic et votre lettre part",
        blocks(pending),
        {"Send my letter", "Envoyer ma lettre", url},
        notice: true
      )

    new()
    |> to(pending.sender_email)
    |> from(sender())
    |> subject("Confirm and send your letter · Confirmez et envoyez votre lettre")
    |> html_body(html)
    |> text_body(text)
    |> Mailer.deliver()
  end

  defp blocks(pending) do
    [
      {"Your letter to #{pending.recipients} is written and waiting. Press the button and it goes.",
       "Votre lettre à #{pending.recipients} est rédigée et en attente. Appuyez sur le bouton et elle part."},
      {"We ask because your address is the one your MP will reply to, and we will not put an address on a letter to Parliament without knowing it belongs to the person sending it.",
       "Nous le demandons parce que votre adresse est celle à laquelle votre député·e répondra, et nous ne mettons pas une adresse sur une lettre au Parlement sans savoir qu'elle appartient à la personne qui l'envoie."},
      {"The link works for #{PendingLetter.validity_hours()} hours. If you do nothing, the letter is deleted and never sent.",
       "Le lien est valide #{PendingLetter.validity_hours()} heures. Si vous ne faites rien, la lettre est supprimée et n'est jamais envoyée."}
    ]
  end

  defp sender do
    Application.get_env(:pauseai_ca, :campaign_sender, @default_sender)
  end
end
