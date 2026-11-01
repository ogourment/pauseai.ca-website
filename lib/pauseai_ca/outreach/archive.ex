defmodule PauseAiCa.Outreach.Archive do
  @moduledoc "Authored-batch reservation/archive bridge. Generic and authentication mail never enters this module."
  alias PauseAiCa.{Repo, Outreach}
  alias PhoenixCRM.Conversations

  def sender(scope, draft) do
    case Outreach.mailbox_for_draft(scope, draft) do
      {:ok, mailbox} -> {mailbox.name, mailbox.email}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def current?(scope, draft, batch) do
    with {:ok, mailbox} <- Outreach.mailbox_for_draft(scope, draft) do
      mailbox.id == batch.outreach_mailbox_ref and mailbox.email == batch.sender_email and
        mailbox.name == batch.sender_name and mailbox.locale == batch.edition and
        draft.outreach_email == batch.outreach_email and
        draft.conversation_id == batch.conversation_id and
        draft.reply_message_id == batch.reply_message_id and batch.recipient_mode == "outreach"
    else
      _ -> false
    end
  end

  def targets(draft) do
    email = draft.outreach_email

    if PauseAiCa.Outreach.Mailboxes.valid_email?(email) do
      {:ok,
       [
         %{
           id: draft.conversation_id,
           name: "",
           email: email,
           edition: draft.edition,
           status:
             if(PauseAiCa.Newsletters.outreach_eligible?(email), do: :available, else: :excluded)
         }
       ]}
    else
      {:error, :audience_required}
    end
  end

  def headers(email, %{outreach_mailbox_ref: nil}, _delivery), do: email

  def headers(email, batch, delivery) do
    email =
      email
      |> Swoosh.Email.header("Message-ID", message_id(batch, delivery))
      |> Swoosh.Email.reply_to(batch.sender_email)

    case reply(batch) do
      nil ->
        email

      %{rfc_message_id: nil} ->
        email

      message ->
        references =
          Enum.uniq(message.references ++ [message.rfc_message_id]) |> Enum.reject(&is_nil/1)

        email
        |> Swoosh.Email.header("In-Reply-To", message.rfc_message_id)
        |> Swoosh.Email.header("References", Enum.join(references, " "))
    end
  end

  def reserve(%{outreach_mailbox_ref: nil}, _delivery, _email), do: :ok

  def reserve(batch, delivery, email) do
    reply = reply(batch)

    attrs = %{
      direction: :outbound,
      outcome: :pending,
      actor_id: delivery.authorizing_admin_id,
      idempotency_key: "newsletter-delivery:" <> delivery.id,
      delivery_ref: delivery.id,
      rfc_message_id: message_id(batch, delivery),
      in_reply_to: if(reply, do: reply.rfc_message_id),
      references:
        if(reply,
          do: Enum.reject(Enum.uniq(reply.references ++ [reply.rfc_message_id]), &is_nil/1),
          else: []
        ),
      envelope: %{
        "from" => batch.sender_email,
        "to" => [delivery.email],
        "subject" => batch.subject
      },
      body_text: email.text_body,
      body_html: email.html_body,
      source: %{
        "kind" => "authored_outreach",
        "draft_id" => batch.draft_id,
        "batch_id" => batch.id,
        "markdown" => batch.source,
        "environment" => batch.delivery_environment
      },
      occurred_at: delivery.attempted_at
    }

    case Conversations.insert_message(Repo, batch.conversation_id, attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def outcome(%{outreach_mailbox_ref: nil}, _delivery, _state, _provider, _error), do: :ok

  def outcome(batch, delivery, state, provider, error) do
    case Conversations.by_delivery(Repo, batch.outreach_mailbox_ref, delivery.id) do
      nil ->
        Repo.rollback(:missing_archive)

      message ->
        outcome =
          case state do
            "accepted" -> :accepted
            "excluded" -> :failed
            "failed" -> :failed
            _ -> :unknown
          end

        details = %{"delivery_state" => state, "error" => error}

        details =
          if provider in [nil, ""], do: details, else: Map.put(details, "provider_id", provider)

        case Conversations.record_outcome(
               Repo,
               batch.outreach_mailbox_ref,
               message.id,
               outcome,
               details
             ) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  defp reply(%{reply_message_id: nil}), do: nil

  defp reply(batch),
    do:
      Repo.get_by(PhoenixCRM.Message,
        id: batch.reply_message_id,
        conversation_id: batch.conversation_id,
        mailbox_ref: batch.outreach_mailbox_ref
      )

  defp message_id(batch, delivery),
    do:
      "<outreach-" <>
        delivery.id <> "@" <> (batch.sender_email |> String.split("@") |> List.last()) <> ">"
end
