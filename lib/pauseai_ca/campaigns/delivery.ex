defmodule PauseAiCa.Campaigns.Delivery do
  @moduledoc """
  Sends a campaign letter to a member of parliament on a supporter's behalf.

  This is the assisted path. The supporter reviews the letter, gives explicit
  consent, and we send it. Two rules shape the implementation:

    * The letter is sent **from** a PauseAI Canada address with the supporter's
      address as `reply-to`. We never forge a `From:` header, so the MP's office
      can see who is writing and reply to them directly.
    * We keep nothing. The supporter's name, email and postal code are used to
      build the message and are then discarded. Counting how many letters were
      sent is a separate, deliberate decision that needs the privacy review in
      the guide first.

  The DIY path in `PauseAiCa.Campaigns.Letter.mailto/1` remains available and
  requires no personal data to reach us at all.
  """

  import Swoosh.Email

  alias PauseAiCa.Campaigns.Letter
  alias PauseAiCa.Mailer

  # The only sender verified in PauseAI Canada's Brevo account.
  @default_sender {"PauseAI Canada", "pauseaicanada@proton.me"}

  @doc """
  Sends `letter` on behalf of `supporter`.

  `supporter` must include `:name` and `:email`. Returns `{:error, :invalid_email}`
  rather than sending when we cannot give the MP a working reply address, and
  `{:error, :no_recipient}` when no MP was resolved.
  """
  @spec deliver(Letter.t(), map()) :: {:ok, term()} | {:error, atom()}
  def deliver(%Letter{} = letter, supporter) do
    with {:ok, reply_to} <- validate_email(supporter[:email]),
         {:ok, recipients} <- validate_recipients(letter.to) do
      letter
      |> build(supporter[:name], reply_to, recipients)
      |> Mailer.deliver()
      |> case do
        {:ok, result} -> {:ok, result}
        {:error, _reason} -> {:error, :delivery_failed}
      end
    end
  end

  defp build(letter, name, reply_to, recipients) do
    new()
    |> from(sender())
    |> reply_to({presence(name) || reply_to, reply_to})
    |> to(recipients)
    |> subject(letter.subject)
    |> text_body(letter.body <> attribution(name, reply_to))
  end

  # The MP's office needs to know this arrived through a campaign tool and who
  # it actually came from. Hiding that would be a disservice to both sides.
  defp attribution(name, reply_to) do
    "\n\n---\nSent through pauseai.ca on behalf of #{presence(name) || reply_to} <#{reply_to}>.\n" <>
      "Envoyé via pauseai.ca au nom de #{presence(name) || reply_to} <#{reply_to}>.\n"
  end

  defp validate_email(email) when is_binary(email) do
    trimmed = String.trim(email)

    if Regex.match?(~r/^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$/, trimmed) do
      {:ok, trimmed}
    else
      {:error, :invalid_email}
    end
  end

  defp validate_email(_email), do: {:error, :invalid_email}

  defp validate_recipients(to) when is_binary(to) do
    case to
         |> String.split(",", trim: true)
         |> Enum.map(&String.trim/1)
         |> Enum.reject(&(&1 == "")) do
      [] -> {:error, :no_recipient}
      recipients -> {:ok, recipients}
    end
  end

  defp validate_recipients(_to), do: {:error, :no_recipient}

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil

  defp sender do
    Application.get_env(:pauseai_ca, :campaign_sender, @default_sender)
  end
end
