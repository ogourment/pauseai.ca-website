defmodule PauseAiCa.Outreach.HistoricalImport do
  @moduledoc "Explicit, administrator-confirmed historical mail intake without delivery or notification."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers}
  alias PauseAiCa.Outreach.{Mailboxes, Access}
  alias PhoenixCRM.{Conversations, Conversation, Message, Address, Person}
  alias PhoenixMailWorkflow.HistoricalEmail

  def preview(scope, mailbox_ref, raw) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, mailbox} <- Mailboxes.fetch(scope, mailbox_ref),
         {:ok, message} <- HistoricalEmail.parse(raw) do
      rows = participants(message) |> Enum.map(&match_contact/1)
      existing = find_existing(mailbox.id, message.rfc_message_id)

      {:ok,
       %{
         message: message,
         contacts: rows,
         mailbox: mailbox,
         existing: existing,
         match_fingerprint: match_fingerprint(rows)
       }}
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  def confirm(scope, mailbox_ref, raw, expected_matches, context) do
    with {:ok, preview} <- preview(scope, mailbox_ref, raw),
         true <- preview.match_fingerprint == expected_matches,
         true <- is_binary(context) and String.length(context) <= 200 do
      Repo.transaction(fn ->
        Access.lock!(scope, mailbox_ref)
        if not Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)

        case Conversations.with_mailbox_lock(Repo, mailbox_ref, fn ->
               record!(scope, preview, raw, String.trim(context))
             end) do
          {:ok, result} -> result
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      false -> {:error, :preview_changed}
      error -> error
    end
  end

  defp record!(scope, preview, raw, context) do
    message = preview.message

    case find_existing(preview.mailbox.id, message.rfc_message_id) do
      nil ->
        insert!(scope, preview, raw, context)

      existing ->
        if same_source?(existing, raw),
          do: %{message: existing, duplicate?: true},
          else: Repo.rollback(:identity_conflict)
    end
  end

  # Browsers paste LF line endings while .eml exports commonly use CRLF.
  # Retain the first original bytes and compare equivalent transport line endings.
  defp same_source?(existing, raw) do
    with "historical_import" <- existing.source["kind"],
         {:ok, original} <- Base.decode64(existing.source["original_eml"] || "") do
      String.replace(original, "\r\n", "\n") == String.replace(raw, "\r\n", "\n")
    else
      _ -> false
    end
  end

  defp insert!(scope, preview, raw, context) do
    message = preview.message
    participants = participants(message)

    conversation =
      case Conversations.find_thread(Repo, preview.mailbox.id, participants, [
             message.in_reply_to | message.references
           ]) do
        {:ok, conversation} ->
          conversation

        {:error, reason} when reason in [:not_found, :ambiguous] ->
          case Conversations.create(Repo, %{
                 mailbox_ref: preview.mailbox.id,
                 participants: participants,
                 subject: message.envelope["subject"],
                 actor_id: scope.user.id
               }) do
            {:ok, conversation} -> conversation
            {:error, reason} -> Repo.rollback(reason)
          end
      end

    attrs =
      Map.take(message, [
        :envelope,
        :rfc_message_id,
        :in_reply_to,
        :references,
        :occurred_at,
        :body_text,
        :body_html
      ])

    attrs = Map.put(attrs, :body_text, message.body_text || message.body_html)

    attrs =
      Map.merge(attrs, %{
        direction: :inbound,
        outcome: :received,
        actor_id: scope.user.id,
        source: %{
          "kind" => "historical_import",
          "sha256" => message.fingerprint,
          "context" => context,
          "original_eml" => Base.encode64(raw)
        }
      })

    case Conversations.insert_message(Repo, conversation.id, attrs) do
      {:ok, saved} -> %{message: saved, duplicate?: false}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def contact_history(scope, addresses) do
    with true <- Volunteers.superadmin?(scope), {:ok, boxes} <- Mailboxes.all(scope) do
      refs = Enum.map(boxes, & &1.id)
      emails = Enum.map(addresses, & &1.email)

      Repo.all(
        from c in Conversation,
          where:
            c.mailbox_ref in ^refs and fragment("? && ?::varchar[]", c.participants, ^emails),
          order_by: [desc: c.updated_at],
          limit: 100
      )
    else
      _ -> []
    end
  end

  defp find_existing(ref, id),
    do:
      Repo.one(
        from m in Message, where: m.mailbox_ref == ^ref and m.rfc_message_id == ^id, limit: 1
      )

  defp participants(message),
    do:
      Conversation.normalize_participants([
        message.envelope["from"]
        | message.envelope["to"] ++ message.envelope["cc"] ++ message.envelope["bcc"]
      ])

  defp match_contact(email) do
    case Repo.get_by(Address, email: email) do
      nil ->
        %{email: email, person_id: nil, name: nil}

      address ->
        person = Repo.get!(Person, address.person_id)
        person = Repo.get!(Person, person.canonical_id || person.id)
        %{email: email, person_id: person.id, name: person.name}
    end
  end

  defp match_fingerprint(rows),
    do:
      rows
      |> Enum.map(&{&1.email, &1.person_id})
      |> :erlang.term_to_binary()
      |> HistoricalEmail.fingerprint()
end
