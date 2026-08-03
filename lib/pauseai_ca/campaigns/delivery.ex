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

  ## Rehearsal mode

  Any environment that is not production must set
  `config :pauseai_ca, :campaign_rehearsal, true`. Letters are then delivered to
  the supporter instead of the member of parliament, with the real recipient
  named in a `STAGING` subject prefix and a banner at the top of the body. The
  whole flow can be exercised without a single MP office receiving test mail.
  """

  import Swoosh.Email

  alias PauseAiCa.Campaigns.Letter
  alias PauseAiCa.Mailer

  # Verified sender on the authenticated pauseai.ca domain. Replies to a
  # supporter's letter go to the supporter; anything else lands in info@.
  @default_sender {"PauseAI Canada", "info@pauseai.ca"}

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

  @doc """
  True when letters are being diverted to the supporter rather than sent to an
  MP. The page says so before anyone presses send.
  """
  @spec rehearsal?() :: boolean()
  def rehearsal?, do: Application.get_env(:pauseai_ca, :campaign_rehearsal, false)

  defp build(letter, name, reply_to, recipients) do
    body = letter.body <> attribution(name, reply_to)

    {to, subject_line, body} =
      if rehearsal?() do
        {[reply_to], "[STAGING → #{Enum.join(recipients, ", ")}] " <> letter.subject,
         rehearsal_banner(recipients) <> body}
      else
        {recipients, letter.subject, body}
      end

    new()
    |> from(sender())
    |> reply_to({presence(name) || reply_to, reply_to})
    |> to(to)
    |> subject(subject_line)
    |> text_body(body)
    |> html_body(html_body(body))
  end

  defp rehearsal_banner(recipients) do
    """
    ===========================================================
    STAGING — this letter was NOT sent to a member of parliament.
    On the live site it would have gone to: #{Enum.join(recipients, ", ")}
    ===========================================================

    """
  end

  # The MP's office needs to know this arrived through a campaign tool and who
  # it actually came from. Hiding that would be a disservice to both sides.
  defp attribution(name, reply_to) do
    "\n\n---\nSent through pauseai.ca on behalf of #{presence(name) || reply_to} <#{reply_to}>.\n" <>
      "Envoyé via pauseai.ca au nom de #{presence(name) || reply_to} <#{reply_to}>.\n"
  end

  # When we send, we control the message, so the three asks can actually be
  # emphasised. The DIY mailto path cannot do this — mailto: bodies are plain
  # text — which is one concrete reason to let us send it.
  defp html_body(body) do
    paragraphs =
      body
      |> String.split(~r/\n{2,}/, trim: true)
      |> Enum.map_join("\n", fn paragraph ->
        text =
          paragraph
          |> String.trim()
          |> escape()
          |> String.replace(~r/\n/, "<br />")
          |> emphasise_asks()

        ~s(<p style="margin:0 0 16px;">#{text}</p>)
      end)

    """
    <!DOCTYPE html>
    <html><body style="margin:0;padding:0;">
      <div style="font-family:Georgia,'Times New Roman',serif;font-size:15px;
                  line-height:1.65;color:#1c1917;max-width:640px;">
        #{paragraphs}
      </div>
    </body></html>
    """
  end

  # A numbered ask reads as an ask. Everything else is left alone.
  defp emphasise_asks(text) do
    Regex.replace(~r/^(\d\.\s)(.+)$/u, text, fn _whole, number, rest ->
      "#{number}<strong>#{rest}</strong>"
    end)
  end

  defp escape(value) do
    value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
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
