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

  alias PauseAiCa.Campaigns.SendIntents
  alias PauseAiCa.Campaigns.Letter
  alias PauseAiCa.Campaigns.PendingLetter
  alias PauseAiCa.Repo

  @doc """
  Stores `letter` and returns the token to email to `supporter`.
  """
  @spec hold(Letter.t(), map(), String.t()) ::
          {:ok, String.t(), PendingLetter.t()} | {:error, Ecto.Changeset.t()}
  def hold(%Letter{} = letter, supporter, locale),
    do: insert_pending(letter, supporter, locale, nil)

  def hold(%Letter{} = letter, supporter, locale, opts) do
    Repo.transaction(fn ->
      with {:ok, intent} <-
             SendIntents.prepare(
               nil,
               letter,
               supporter,
               "assisted",
               Keyword.put(opts, :await_confirmation, true)
             ) do
        intent =
          Repo.one!(
            from(i in PauseAiCa.Campaigns.SendIntent,
              where: i.id == ^intent.id,
              lock: "FOR UPDATE"
            )
          )

        pending = Repo.get_by(PendingLetter, send_intent_id: intent.id)

        if intent.state in ["accepted", "submitting", "unknown"] or
             intent.error_code in ~w(confirmation_submitting confirmation_unknown),
           do: Repo.rollback(:delivery_unknown)

        renew? =
          pending &&
            (DateTime.compare(pending.expires_at, DateTime.utc_now()) != :gt or
               intent.error_code in ~w(confirmation_rejected confirmation_pending))

        if pending && not renew? do
          {nil, pending}
        else
          case PauseAiCa.Campaigns.RateLimit.check(
                 String.downcase(String.trim(supporter[:email]))
               ) do
            :ok -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end

          {token, pending} =
            if pending do
              {token, changeset} = PendingLetter.renew_token(pending)
              {token, Repo.update!(changeset)}
            else
              case insert_pending(letter, supporter, locale, intent.id) do
                {:ok, token, pending} -> {token, pending}
                {:error, changeset} -> Repo.rollback(changeset)
              end
            end

          Repo.update!(
            Ecto.Changeset.change(intent,
              state: "awaiting_confirmation",
              error_code: "confirmation_pending"
            )
          )

          {token, pending}
        end
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {token, pending}} -> {:ok, token, pending}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Submit a confirmation notification once and retain an uncertain outcome instead of blindly retrying."
  def notify(%PendingLetter{send_intent_id: id} = pending, token, deliver)
      when is_binary(id) and is_function(deliver, 2) do
    result =
      Repo.transaction(fn ->
        intent =
          Repo.one!(
            from(i in PauseAiCa.Campaigns.SendIntent, where: i.id == ^id, lock: "FOR UPDATE")
          )

        current = Repo.get(PendingLetter, pending.id)

        unless current && DateTime.compare(current.expires_at, DateTime.utc_now()) == :gt,
          do: Repo.rollback(:not_found)

        cond do
          intent.state in ["accepted", "submitting", "unknown"] ->
            Repo.rollback(:delivery_unknown)

          is_nil(token) and intent.error_code == "confirmation_accepted" ->
            :already_notified

          is_nil(token) ->
            Repo.rollback(:delivery_unknown)

          intent.error_code != "confirmation_pending" ->
            Repo.rollback(:delivery_unknown)

          true ->
            unless PendingLetter.hash(token) == {:ok, current.token},
              do: Repo.rollback(:not_found)

            Repo.update!(Ecto.Changeset.change(intent, error_code: "confirmation_submitting"))
            {:send, current}
        end
      end)

    case result do
      {:ok, :already_notified} -> :ok
      {:ok, {:send, current}} -> deliver_notification(current, token, deliver)
      {:error, reason} -> {:error, reason}
    end
  end

  def notify(_, _, _), do: {:error, :delivery_unknown}

  defp deliver_notification(pending, token, deliver) do
    result =
      try do
        deliver.(pending, token)
      rescue
        _ -> {:error, :uncertain}
      catch
        _, _ -> {:error, :uncertain}
      end

    {code, response} =
      case result do
        {:ok, _} ->
          {"confirmation_accepted", :ok}

        {:error, reason} ->
          if SendIntents.definitive_rejection?(reason),
            do: {"confirmation_rejected", {:error, :delivery_failed}},
            else: {"confirmation_unknown", {:error, :delivery_unknown}}

        _ ->
          {"confirmation_unknown", {:error, :delivery_unknown}}
      end

    case Repo.transaction(fn ->
           intent =
             Repo.one!(
               from(i in PauseAiCa.Campaigns.SendIntent,
                 where: i.id == ^pending.send_intent_id,
                 lock: "FOR UPDATE"
               )
             )

           current = Repo.get(PendingLetter, pending.id)
           # Token release may already have advanced the MP submission. Preserve that outcome.
           if (current && current.token == pending.token) and
                intent.state == "awaiting_confirmation" and
                intent.error_code == "confirmation_submitting",
              do: Repo.update!(Ecto.Changeset.change(intent, error_code: code))
         end) do
      {:ok, _} -> response
      {:error, _} -> {:error, :delivery_unknown}
    end
  rescue
    _ -> {:error, :delivery_unknown}
  end

  @doc "Bounded confirmation language and opaque operator reference, without exposing letter contents."
  def context(token) do
    with {:ok, hashed} <- PendingLetter.hash(token),
         %PendingLetter{} = pending <- Repo.get_by(PendingLetter, token: hashed),
         do: %{locale: pending.locale, intent_reference: pending.send_intent_id},
         else: (_ -> nil)
  end

  defp insert_pending(letter, supporter, locale, intent_id) do
    {token, changeset} =
      PendingLetter.build(%{
        sender_name: supporter[:name],
        sender_email: supporter[:email],
        recipients: letter.to,
        subject: letter.subject,
        body: letter.body,
        locale: locale,
        send_intent_id: intent_id
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
      case SendIntents.release(pending) do
        {:ok, _result} ->
          # The queue entry has done its job; nothing about the sender is kept.
          Repo.delete_all(from p in PendingLetter, where: p.id == ^pending.id)
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
