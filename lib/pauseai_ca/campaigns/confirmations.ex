defmodule PauseAiCa.Campaigns.Confirmations do
  @moduledoc """
  Holds a letter until the sender proves the address is theirs, then sends it.

  Two paths reach a member of parliament:

    * a signed-in supporter with a confirmed address sends immediately, because
      the address has already been proved and asking twice is friction for
      nothing;
    * anyone else gets one email, and clicking the link in it releases the
      letter.

  The second path exists because reply-to is what an MP's office will answer.
  Without it, anyone could put a third party's address on a letter to
  Parliament.
  """

  import Ecto.Query

  alias PauseAiCa.Campaigns.Delivery
  alias PauseAiCa.Campaigns.Letter
  alias PauseAiCa.Campaigns.PendingLetter
  alias PauseAiCa.Repo

  @doc """
  Stores `letter` and returns the token to email to `supporter`.
  """
  @spec hold(Letter.t(), map(), String.t()) ::
          {:ok, String.t(), PendingLetter.t()} | {:error, Ecto.Changeset.t()}
  def hold(%Letter{} = letter, supporter, locale) do
    {token, changeset} =
      PendingLetter.build(%{
        sender_name: supporter[:name],
        sender_email: supporter[:email],
        recipients: letter.to,
        subject: letter.subject,
        body: letter.body,
        locale: locale
      })

    case Repo.insert(changeset) do
      {:ok, pending} -> {:ok, token, pending}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Releases the letter behind `token`.

  Returns `{:error, :not_found}` for an unknown, expired or already-used token —
  the same answer in every case, so the endpoint cannot be used to probe which
  tokens exist.
  """
  @spec release(String.t()) :: {:ok, map()} | {:error, :not_found | atom()}
  def release(token) do
    with {:ok, hashed} <- PendingLetter.hash(token),
         %PendingLetter{} = pending <- fetch_live(hashed) do
      letter = %Letter{to: pending.recipients, subject: pending.subject, body: pending.body}
      supporter = %{name: pending.sender_name, email: pending.sender_email}

      case Delivery.deliver(letter, supporter) do
        {:ok, _result} ->
          # The queue entry has done its job; nothing about the sender is kept.
          Repo.delete(pending)
          {:ok, %{locale: pending.locale, recipients: pending.recipients}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      _unknown_or_expired -> {:error, :not_found}
    end
  end

  @doc """
  Deletes expired letters. Safe to call repeatedly.
  """
  @spec sweep() :: {integer(), nil}
  def sweep do
    now = DateTime.utc_now()
    Repo.delete_all(from p in PendingLetter, where: p.expires_at < ^now)
  end

  defp fetch_live(hashed) do
    now = DateTime.utc_now()
    Repo.one(from p in PendingLetter, where: p.token == ^hashed and p.expires_at > ^now)
  end
end
