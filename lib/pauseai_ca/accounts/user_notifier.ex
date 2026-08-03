defmodule PauseAiCa.Accounts.UserNotifier do
  @moduledoc """
  Transactional email for sign-in and account changes.

  Sent from the authenticated pauseai.ca domain and laid out in the PauseAI
  Canada look. Every message is bilingual: we do not know which language a
  recipient reads, and a sign-in link is the wrong place to guess.
  """

  import Swoosh.Email

  alias PauseAiCa.Accounts.User
  alias PauseAiCa.Mailer
  alias PauseAiCaWeb.Emails.Layout

  @default_sender {"PauseAI Canada", "info@pauseai.ca"}

  defp deliver(recipient, subject, {html, text}) do
    email =
      new()
      |> to(recipient)
      |> from(sender())
      |> subject(subject)
      |> html_body(html)
      |> text_body(text)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp sender do
    Application.get_env(:pauseai_ca, :campaign_sender, @default_sender)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(
      user.email,
      "Confirm your new address · Confirmez votre nouvelle adresse",
      Layout.render(
        "Confirm your new address",
        "Confirmez votre nouvelle adresse",
        [
          {"You asked to change the email address on your PauseAI Canada account to #{user.email}. Use the button below to confirm it.",
           "Vous avez demandé de remplacer l'adresse courriel de votre compte PauseAI Canada par #{user.email}. Utilisez le bouton ci-dessous pour la confirmer."},
          {"If you did not ask for this, ignore this message and nothing will change.",
           "Si vous n'êtes pas à l'origine de cette demande, ignorez ce message: rien ne changera."}
        ],
        {"Confirm address", "Confirmer l'adresse", url}
      )
    )
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(
      user.email,
      "Your sign-in link · Votre lien de connexion",
      Layout.render(
        "Your sign-in link",
        "Votre lien de connexion",
        [
          {"Use the button below to sign in to PauseAI Canada. The link works once and expires shortly.",
           "Utilisez le bouton ci-dessous pour vous connecter à PauseAI Canada. Le lien fonctionne une seule fois et expire rapidement."},
          {"If you did not ask to sign in, you can ignore this message.",
           "Si vous n'avez pas demandé à vous connecter, ignorez ce message."}
        ],
        {"Sign in", "Se connecter", url}
      )
    )
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      "Confirm your account · Confirmez votre compte",
      Layout.render(
        "Confirm your account",
        "Confirmez votre compte",
        [
          {"Welcome. Confirm this address to finish setting up your PauseAI Canada account.",
           "Bienvenue. Confirmez cette adresse pour terminer la création de votre compte PauseAI Canada."},
          {"Confirming proves the address is yours. We use it to sign you in, and never sell or share it.",
           "La confirmation prouve que l'adresse est bien la vôtre. Elle sert à vous connecter et n'est jamais vendue ni partagée."},
          {"If you did not create an account, you can ignore this message.",
           "Si vous n'avez pas créé de compte, ignorez ce message."}
        ],
        {"Confirm account", "Confirmer le compte", url}
      )
    )
  end
end
