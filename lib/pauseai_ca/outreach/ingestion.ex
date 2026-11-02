defmodule PauseAiCa.Outreach.Ingestion do
  @moduledoc "Durable webhook intake, then bounded local normalization/threading. Caller authenticates transport; no HTTP occurs here."
  import Ecto.Query
  alias PauseAiCa.Repo
  alias PauseAiCa.Outreach.{Receipt, Mailboxes, Notifications}
  alias PhoenixCRM.{Conversations, ReceiptStore}

  def receive(payload), do: ReceiptStore.receive(Repo, Receipt, payload)
  def pending_receipts(limit), do: ReceiptStore.pending(Repo, Receipt, limit)

  def record_processing_failure(id, reason),
    do: ReceiptStore.record_failure(Repo, Receipt, id, reason)

  def retry_receipt(scope, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      Repo.transaction(fn ->
        receipt = ReceiptStore.lock!(Repo, Receipt, uuid)
        if not receipt_allowed?(scope, receipt), do: Repo.rollback(:unauthorized)

        unless PauseAiCa.Volunteers.superadmin?(scope) do
          {refs, true} = receipt_scope(receipt)
          Enum.each(Enum.sort(refs), &PauseAiCa.Outreach.Access.lock!(scope, &1))
        end

        ReceiptStore.retry_locked!(Repo, receipt)
      end)
    else
      _ -> {:error, :unauthorized}
    end
  end

  def processing(scope) do
    if PauseAiCa.Volunteers.superadmin?(scope) or PauseAiCa.Outreach.access?(scope) do
      Repo.all(
        from(r in Receipt,
          where: r.state in ["pending", "failed", "quarantined"] or r.files_pending,
          order_by: [desc: r.inserted_at],
          limit: 50
        )
      )
      |> Enum.filter(&receipt_allowed?(scope, &1))
      |> Enum.map(
        &Map.take(&1, [:id, :state, :error, :attempts, :files_pending, :next_attempt_at])
      )
    else
      []
    end
  end

  defp receipt_allowed?(scope, receipt) do
    if PauseAiCa.Volunteers.superadmin?(scope) do
      true
    else
      {refs, complete?} = receipt_scope(receipt)
      PauseAiCa.Outreach.Access.covers?(scope, refs, complete?)
    end
  end

  defp receipt_scope(receipt) do
    rules =
      Enum.map(
        Mailboxes.configured(),
        &%{id: &1.id, receiving_addresses: &1.receiving_addresses, root_addresses: [&1.email]}
      )

    case PhoenixMailWorkflow.Inbound.Brevo.normalize(receipt.payload, rules) do
      {:ok, result} ->
        refs = result.messages |> Enum.map(& &1.mailbox_id) |> Enum.uniq()
        {refs, result.messages != [] and result.quarantined == []}

      _ ->
        {[], false}
    end
  end

  def ingest(payload) do
    with {:ok, receipt} <- __MODULE__.receive(payload), do: process_receipt(receipt.id)
  end

  def process_receipt(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id) do
      Repo.transaction(fn ->
        receipt =
          Repo.one(from(r in Receipt, where: r.id == ^uuid, lock: "FOR UPDATE")) ||
            Repo.rollback(:not_found)

        cond do
          receipt.state in ["processed", "quarantined"] ->
            %{receipt: receipt, messages: [], quarantined: receipt.quarantined}

          receipt.state == "failed" ->
            Repo.rollback(:retry_required)

          true ->
            process!(receipt)
        end
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  defp process!(receipt) do
    boxes = Mailboxes.configured()

    rules =
      Enum.map(
        boxes,
        &%{id: &1.id, receiving_addresses: &1.receiving_addresses, root_addresses: [&1.email]}
      )

    case PhoenixMailWorkflow.Inbound.Brevo.normalize(receipt.payload, rules) do
      {:ok, result} ->
        messages =
          Enum.map(result.messages, fn incoming ->
            box =
              Enum.find(boxes, &(&1.id == incoming.mailbox_id)) ||
                Repo.rollback(:mailbox_unavailable)

            # Activation is required before inbound source becomes visible or notifies anyone.
            if not box.enabled? or not box.verified?, do: Repo.rollback(:mailbox_unavailable)
            store!(receipt, box, incoming)
          end)

        quarantined =
          Enum.map(result.quarantined, fn row ->
            Map.new(row, fn {k, v} ->
              {to_string(k), if(is_atom(v), do: to_string(v), else: v)}
            end)
          end)

        saved =
          Repo.update!(
            Ecto.Changeset.change(receipt,
              state: if(messages == [], do: "quarantined", else: "processed"),
              quarantined: quarantined,
              files_pending: Enum.any?(result.messages, &(&1.attachments != [])),
              processed_at: receipt.processed_at || DateTime.utc_now()
            )
          )

        %{receipt: saved, messages: messages, quarantined: quarantined}

      {:error, reason} ->
        saved =
          Repo.update!(
            Ecto.Changeset.change(receipt,
              state: "quarantined",
              error: to_string(reason),
              processed_at: receipt.processed_at || DateTime.utc_now()
            )
          )

        %{receipt: saved, messages: [], quarantined: [%{"reason" => to_string(reason)}]}
    end
  end

  defp store!(receipt, box, incoming) do
    case Conversations.with_mailbox_lock(Repo, box.id, fn ->
           identity = %{
             provider_id: List.first(incoming.provider_ids),
             rfc_message_id: incoming.rfc_message_id
           }

           existing =
             case Conversations.find_inbound(Repo, box.id, identity) do
               {:ok, message} -> message
               {:error, :not_found} -> nil
               {:error, reason} -> Repo.rollback(reason)
             end

           conversation =
             if existing,
               do: Conversations.get(Repo, box.id, existing.conversation_id),
               else: thread!(box, incoming)

           source = %{
             "provider" => "brevo",
             "receipt_id" => receipt.id,
             "item_index" => incoming.source_index,
             "markdown" => incoming.markdown_body
           }

           source =
             if existing,
               do: Map.merge(source, Map.take(existing.source, ["receipt_id", "item_index"])),
               else: source

           attachments =
             Enum.map(incoming.attachments, fn attachment ->
               attachment
               |> Map.new(fn {key, value} -> {to_string(key), value} end)
               |> Map.put("attachment_index", attachment.index)
             end)

           attrs = %{
             direction: :inbound,
             outcome: :received,
             actor_id: "system:brevo-inbound",
             provider_id: identity.provider_id,
             rfc_message_id: incoming.rfc_message_id,
             in_reply_to: incoming.in_reply_to,
             references: incoming.references,
             envelope: %{
               "from" => incoming.sender_email,
               "from_name" => incoming.sender_name,
               "to" => addresses(incoming.to),
               "cc" => addresses(incoming.cc),
               "subject" => incoming.subject,
               "reply_to" => incoming.reply_to
             },
             body_text: incoming.text_body,
             body_html: incoming.html_body,
             source: source,
             attachments: attachments,
             occurred_at: incoming.sent_at
           }

           message =
             case Conversations.insert_message(Repo, conversation.id, attrs) do
               {:ok, message} -> message
               {:error, reason} -> Repo.rollback(reason)
             end

           Notifications.enqueue!(message, conversation, box)
           message
         end) do
      {:ok, message} -> message
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp thread!(box, incoming) do
    internals =
      MapSet.new([
        String.downcase(box.email) | Enum.map(box.receiving_addresses, &String.downcase/1)
      ])

    external =
      [incoming.sender_email | addresses(incoming.to) ++ addresses(incoming.cc)]
      |> Enum.reject(&MapSet.member?(internals, String.downcase(&1)))

    participants = [box.email | external] |> PhoenixCRM.Conversation.normalize_participants()

    case Conversations.find_thread(Repo, box.id, participants, [
           incoming.in_reply_to | incoming.references
         ]) do
      {:ok, conversation} ->
        conversation

      {:error, reason} when reason in [:not_found, :ambiguous] ->
        case Conversations.create(Repo, %{
               mailbox_ref: box.id,
               participants: participants,
               subject: incoming.subject,
               actor_id: "system:brevo-inbound"
             }) do
          {:ok, conversation} -> conversation
          {:error, error} -> Repo.rollback(error)
        end
    end
  end

  defp addresses(rows), do: Enum.map(rows, & &1.email)
end
