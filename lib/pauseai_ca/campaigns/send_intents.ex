defmodule PauseAiCa.Campaigns.SendIntents do
  @moduledoc """
  Campaign-specific durable send reservations using the existing Mailer boundary.
  An accepted provider result and its actor-owned action settle together. A crash
  after reservation or uncertain provider outcome retains the hold and requires
  reconciliation. Neither provider acceptance nor a self-confirmed handoff proves
  that an MP read a letter. No letter body or sender address is retained here.
  """
  import Ecto.Query
  alias PauseAiCa.{Accounts, Engagement, Repo}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Campaigns.{Delivery, Letter, PendingLetter, RateLimit, SendIntent}

  def verified_sender?(%Scope{user: %{id: id}}, email) when is_binary(email) do
    case Repo.get(Accounts.User, id) do
      %{confirmed_at: %DateTime{}, email: current} -> normalize(email) == normalize(current)
      _ -> false
    end
  end

  def verified_sender?(_, _), do: false

  def deliver(%Scope{} = scope, %Letter{} = letter, supporter, opts \\ []) do
    if verified_sender?(scope, supporter[:email]),
      do: submit(scope, letter, supporter, opts),
      else: {:error, :sender_unverified}
  end

  @doc "Only the existing verified token-release path calls this anonymous entry point."
  def release(%PendingLetter{} = pending) do
    letter = %Letter{to: pending.recipients, subject: pending.subject, body: pending.body}

    submit(nil, letter, %{name: pending.sender_name, email: pending.sender_email},
      intent_id: pending.send_intent_id
    )
  end

  def handoff(%Scope{} = scope, %Letter{} = letter, supporter, opts \\ []) do
    with true <- verified_sender?(scope, supporter[:email]),
         {:ok, intent} <- prepare(scope, letter, supporter, "handoff", opts) do
      Repo.transaction(fn ->
        row = locked!(intent.id)

        unless row.actor_id == scope.user.id and verified_sender?(scope, supporter[:email]),
          do: Repo.rollback(:sender_unverified)

        if row.action_id do
          row
        else
          action = create_action!(scope, false)
          Repo.update!(Ecto.Changeset.change(row, state: "handoff", action_id: action.id))
        end
      end)
    else
      _ -> {:error, :sender_unverified}
    end
  end

  @doc "A bounded, keyed identity survives duplicate submits/reconnect without storing the private letter."
  def prepare(scope, %Letter{} = letter, supporter, kind, opts \\ [])
      when kind in ~w(assisted handoff) do
    with true <- valid_letter?(letter),
         true <- is_binary(supporter[:email]),
         {:ok, template} <- template(Keyword.get(opts, :template)) do
      actor = if scope, do: scope.user.id
      key = Application.fetch_env!(:pauseai_ca, PauseAiCaWeb.Endpoint)[:secret_key_base]

      payload =
        {actor, kind, letter.to, letter.subject, letter.body, String.trim(supporter[:name] || ""),
         normalize(supporter[:email]), template}

      fingerprint = :crypto.mac(:hmac, :sha256, key, :erlang.term_to_binary(payload))
      id = Ecto.UUID.generate()
      now = DateTime.utc_now()

      attrs = %{
        id: id,
        fingerprint: fingerprint,
        actor_id: actor,
        kind: kind,
        state:
          if(Keyword.get(opts, :await_confirmation), do: "awaiting_confirmation", else: "ready"),
        template_id: template[:id],
        template_revision: template[:revision],
        inserted_at: now,
        updated_at: now
      }

      Repo.insert_all(SendIntent, [attrs], on_conflict: :nothing, conflict_target: :fingerprint)
      {:ok, Repo.get_by!(SendIntent, fingerprint: fingerprint)}
    else
      _ -> {:error, :invalid_letter}
    end
  end

  defp submit(scope, letter, supporter, opts) do
    with {:ok, intent} <- intent(scope, letter, supporter, opts),
         {:ok, result} <- claim(intent, scope, supporter) do
      case result do
        {:accepted, row} -> {:ok, row}
        {:send, row} -> perform(scope, row, letter, supporter, opts)
      end
    end
  end

  defp intent(scope, letter, supporter, opts) do
    case opts[:intent_id] do
      nil ->
        prepare(scope, letter, supporter, "assisted", opts)

      id ->
        case Repo.one(
               from(i in SendIntent,
                 where: i.id == ^id and is_nil(i.actor_id) and i.kind == "assisted"
               )
             ) do
          nil -> {:error, :invalid_letter}
          intent -> {:ok, intent}
        end
    end
  end

  defp claim(intent, scope, supporter) do
    Repo.transaction(fn ->
      row = locked!(intent.id)

      if scope &&
           (row.actor_id != scope.user.id or not verified_sender?(scope, supporter[:email])),
         do: Repo.rollback(:sender_unverified)

      case row.state do
        "accepted" ->
          {:accepted, row}

        state when state in ~w(ready rejected awaiting_confirmation) ->
          if scope do
            case RateLimit.check(normalize(supporter[:email])) do
              :ok -> :ok
              {:error, reason} -> Repo.rollback(reason)
            end
          end

          row =
            Repo.update!(
              Ecto.Changeset.change(row,
                state: "submitting",
                attempted_at: DateTime.utc_now(),
                error_code: nil
              )
            )

          {:send, row}

        _ ->
          Repo.rollback(:delivery_unknown)
      end
    end)
  end

  defp perform(scope, intent, letter, supporter, opts) do
    result =
      try do
        if scope && not verified_sender?(scope, supporter[:email]) do
          {:error, :sender_unverified}
        else
          adapter = Keyword.get(opts, :adapter, &Delivery.submit/3)

          adapter.(letter, supporter,
            intent_id: intent.id,
            actor_id: if(scope, do: scope.user.id)
          )
        end
      rescue
        _ -> {:error, :uncertain}
      catch
        _, _ -> {:error, :uncertain}
      end

    settle(intent, scope, result)
  end

  defp settle(intent, scope, {:ok, metadata}) do
    result =
      Repo.transaction(fn ->
        row = locked!(intent.id)

        if row.state == "accepted" do
          row
        else
          unless row.state == "submitting", do: Repo.rollback(:delivery_unknown)
          action = if scope, do: create_action!(scope, true)

          Repo.update!(
            Ecto.Changeset.change(row,
              state: "accepted",
              accepted_at: DateTime.utc_now(),
              action_id: if(action, do: action.id),
              provider_id: provider_id(metadata),
              error_code: nil
            )
          )
        end
      end)

    case result do
      {:ok, row} -> {:ok, row}
      _ -> {:error, :delivery_unknown}
    end
  rescue
    _ -> {:error, :delivery_unknown}
  end

  defp settle(intent, _scope, {:error, reason}) do
    rejected = definitive_rejection?(reason)

    state = if rejected, do: "rejected", else: "unknown"

    case Repo.update(
           Ecto.Changeset.change(intent,
             state: state,
             error_code: if(rejected, do: "delivery_rejected", else: "acceptance_unknown")
           )
         ) do
      {:ok, _} -> {:error, if(rejected, do: :delivery_failed, else: :delivery_unknown)}
      _ -> {:error, :delivery_unknown}
    end
  rescue
    _ -> {:error, :delivery_unknown}
  end

  defp settle(intent, scope, _), do: settle(intent, scope, {:error, :uncertain})
  @doc "True only for a definite pre-submission or explicit provider rejection."
  def definitive_rejection?(reason) do
    reason in [
      :invalid_email,
      :no_recipient,
      :sender_unverified,
      :recipient_delivery_hold,
      :staging_admin_required,
      :mail_environment_blocked,
      :rejected
    ] or explicit_rejection?(reason)
  end

  defp explicit_rejection?({_status, %{"code" => "duplicate_parameter"}}), do: false

  defp explicit_rejection?({status, _}) when status in [400, 401, 402, 403, 404, 413, 422, 429],
    do: true

  defp explicit_rejection?(_), do: false
  defp locked!(id), do: Repo.one!(from(i in SendIntent, where: i.id == ^id, lock: "FOR UPDATE"))

  defp create_action!(scope, confirmed) do
    attrs = %{
      "action_type" => "contacted_representative",
      "happened_on" => Date.utc_today(),
      "confirmed_at" => if(confirmed, do: DateTime.utc_now() |> DateTime.truncate(:second))
    }

    case Engagement.create_action(scope, attrs) do
      {:ok, action} -> action
      _ -> Repo.rollback(:action_record_failed)
    end
  end

  defp valid_letter?(letter),
    do:
      is_binary(letter.subject) and String.length(letter.subject) in 1..998 and
        is_binary(letter.body) and String.length(letter.body) in 1..8000 and
        not Letter.unresolved_placeholders?(letter)

  defp normalize(value), do: value |> String.trim() |> String.downcase()

  defp provider_id(metadata) when is_map(metadata) do
    case metadata[:id] || metadata["messageId"] do
      id when is_binary(id) and byte_size(id) <= 255 -> id
      _ -> nil
    end
  end

  defp provider_id(_), do: nil
  defp template(nil), do: {:ok, %{}}

  defp template(%{id: id, revision: revision}) when is_integer(revision) and revision > 0 do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, %{id: id, revision: revision}}
      _ -> {:error, :invalid_template}
    end
  end

  defp template(_), do: {:error, :invalid_template}
end
