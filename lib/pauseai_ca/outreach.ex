defmodule PauseAiCa.Outreach do
  @moduledoc "Consumer-authorized outreach using the existing draft/review/dispatch workflow and shared CRM archive."
  import Ecto.Query
  alias PauseAiCa.{Repo, Accounts}
  alias PauseAiCa.Newsletters.Draft
  alias PauseAiCa.Outreach.{Access, Mailboxes, Ingestion, Notifications}
  alias PhoenixCRM.Conversations

  def access?(scope), do: match?({:ok, [_ | _]}, Mailboxes.all(scope))
  def mailbox_access(scope), do: Access.management(scope)

  def grant_mailbox(scope, ref, user_id, revision),
    do: Access.grant(scope, ref, user_id, revision)

  def revoke_mailbox(scope, ref, user_id, revision),
    do: Access.revoke(scope, ref, user_id, revision)

  def mailboxes(scope), do: Mailboxes.all(scope)
  def mailbox_for_draft(scope, draft), do: Mailboxes.sending(scope, draft.outreach_mailbox_ref)
  def receive(payload), do: Ingestion.receive(payload)
  def pending_receipts(limit \\ 25), do: Ingestion.pending_receipts(limit)
  def process_receipt(id), do: Ingestion.process_receipt(id)

  def complete_attachments(id),
    do: PhoenixCRM.ReceiptStore.complete_files(Repo, PauseAiCa.Outreach.Receipt, id)

  def record_processing_failure(id, reason), do: Ingestion.record_processing_failure(id, reason)
  def retry_receipt(scope, id), do: Ingestion.retry_receipt(scope, id)
  def ingest(payload), do: Ingestion.ingest(payload)
  def pending_notifications(limit \\ 25), do: Notifications.pending(limit)
  def dispatch_notifications(adapter), do: Notifications.dispatch(adapter)
  def notification_status(scope), do: Notifications.status(scope)

  def list(scope, params \\ %{}) do
    with {:ok, boxes} <- mailboxes(scope),
         true <-
           params["mailbox_ref"] in [nil, ""] or
             Enum.any?(boxes, &(&1.id == params["mailbox_ref"])) do
      selected = Enum.filter(boxes, &(params["mailbox_ref"] in [nil, "", &1.id]))
      per = positive(params["per"], 25) |> min(100)
      page = positive(params["page"], 1)
      participant = params["email"] || params["contact_email"]
      opts = if is_binary(participant), do: [participant: participant], else: []
      opts = if is_binary(params["q"]), do: Keyword.put(opts, :q, params["q"]), else: opts
      refs = Enum.map(selected, & &1.id)
      total = Conversations.count(Repo, refs, opts)
      pages = max(1, Integer.ceil_div(total, per))
      page = min(page, pages)
      rows = Conversations.list(Repo, refs, opts ++ [limit: per, offset: (page - 1) * per])

      {:ok,
       %{
         conversations: rows,
         mailboxes: boxes,
         page: page,
         pages: pages,
         per: per,
         total: total,
         processing: Ingestion.processing(scope)
       }}
    else
      false -> {:error, :mailbox_unavailable}
      error -> error
    end
  end

  def get(scope, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         {:ok, boxes} <- mailboxes(scope),
         conversation when not is_nil(conversation) <-
           Enum.find_value(boxes, &Conversations.get(Repo, &1.id, uuid)),
         {:ok, mailbox} <- Mailboxes.fetch(scope, conversation.mailbox_ref) do
      messages =
        Conversations.messages(Repo, mailbox.id, uuid, limit: 200, order: :desc) |> Enum.reverse()

      message_count = Conversations.message_count(Repo, mailbox.id, uuid)

      actor_ids =
        Enum.map(messages, & &1.actor_id) |> Enum.filter(&match?({:ok, _}, Ecto.UUID.cast(&1)))

      names =
        Repo.all(from(u in Accounts.User, where: u.id in ^actor_ids, select: {u.id, u.name}))
        |> Map.new()

      decorated =
        Enum.map(
          messages,
          &(Map.from_struct(&1)
            |> Map.put(:actor_name, Map.get(names, &1.actor_id))
            |> PauseAiCa.OutreachAttachments.decorate())
        )

      {:ok,
       %{
         conversation: conversation,
         messages: decorated,
         mailbox: mailbox,
         message_count: message_count,
         truncated?: message_count > length(messages)
       }}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def create_draft(scope, attrs) do
    with {:ok, mailbox} <- Mailboxes.fetch(scope, attrs["mailbox_ref"]),
         {:ok, email} <- email(attrs["email"]) do
      Repo.transaction(fn ->
        fresh!(scope, mailbox.id)
        ensure_identity!(scope, mailbox.id, email)
        conversation = create_conversation!(scope, mailbox, email, attrs["subject"] || "")

        %Draft{
          owner_id: scope.user.id,
          recipient_mode: "outreach",
          outreach_mailbox_ref: mailbox.id,
          conversation_id: conversation.id,
          edition: mailbox.locale,
          outreach_email: email
        }
        |> Draft.changeset(Map.take(attrs, ["subject", "source"]))
        |> insert!()
      end)
    end
  end

  def reply_draft(scope, id) do
    with {:ok, %{conversation: conversation, mailbox: mailbox, messages: messages}} <-
           get(scope, id) do
      external = Enum.reject(conversation.participants, &(&1 == String.downcase(mailbox.email)))

      case external do
        [email] ->
          Repo.transaction(fn ->
            fresh!(scope, mailbox.id)
            latest = List.last(messages)
            subject = conversation.subject || ""
            subject = if Regex.match?(~r/\ARe:/iu, subject), do: subject, else: "Re: " <> subject

            Repo.insert!(%Draft{
              owner_id: scope.user.id,
              recipient_mode: "outreach",
              outreach_mailbox_ref: mailbox.id,
              conversation_id: conversation.id,
              reply_message_id: if(latest, do: latest.id),
              edition: mailbox.locale,
              outreach_email: email,
              subject: subject
            })
          end)

        _ ->
          {:error, :ambiguous_participants}
      end
    end
  end

  def signature_hint(scope, source) do
    if access?(scope) do
      user = Repo.get(Accounts.User, scope.user.id)

      first_name =
        if user && is_binary(user.name), do: user.name |> String.split() |> List.first()

      PhoenixMailWorkflow.Outreach.signature_hint(source, first_name)
    else
      :missing_name
    end
  end

  @doc false
  def validate_changes(scope, draft, changeset) do
    if draft.outreach_mailbox_ref do
      ref = Ecto.Changeset.get_field(changeset, :outreach_mailbox_ref)
      email = Ecto.Changeset.get_field(changeset, :outreach_email)
      mode = Ecto.Changeset.get_field(changeset, :recipient_mode)

      case Mailboxes.fetch(scope, ref) do
        {:ok, mailbox} when mode == "outreach" ->
          Access.lock!(scope, mailbox.id)
          changed? = ref != draft.outreach_mailbox_ref or email != draft.outreach_email

          cond do
            changed? and not is_nil(draft.reply_message_id) ->
              Ecto.Changeset.add_error(
                changeset,
                :outreach_email,
                "cannot change reply participants"
              )

            changed? and changeset.valid? ->
              ensure_identity!(scope, mailbox.id, email)

              conversation =
                create_conversation!(
                  scope,
                  mailbox,
                  email,
                  Ecto.Changeset.get_field(changeset, :subject)
                )

              changeset
              |> Ecto.Changeset.put_change(:conversation_id, conversation.id)
              |> Ecto.Changeset.put_change(:edition, mailbox.locale)

            true ->
              Ecto.Changeset.put_change(changeset, :edition, mailbox.locale)
          end

        _ ->
          Ecto.Changeset.add_error(changeset, :outreach_mailbox_ref, "is unavailable")
      end
    else
      if Ecto.Changeset.get_field(changeset, :recipient_mode) == "outreach" or
           Ecto.Changeset.get_field(changeset, :outreach_mailbox_ref),
         do:
           Ecto.Changeset.add_error(
             changeset,
             :outreach_mailbox_ref,
             "requires an outreach draft"
           ),
         else: changeset
    end
  end

  defp create_conversation!(scope, mailbox, email, subject) do
    case Conversations.create(Repo, %{
           mailbox_ref: mailbox.id,
           participants: [mailbox.email, email],
           subject: subject,
           actor_id: scope.user.id
         }) do
      {:ok, conversation} -> conversation
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp ensure_identity!(scope, ref, email) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1,0))", [
      "outreach-contact:" <> email
    ])

    unless Repo.get_by(PhoenixCRM.Address, email: email) do
      context = PhoenixCRM.new(Repo, PauseAiCa.Outreach.IdentityPolicy)

      case PhoenixCRM.create(context, %{scope: scope, mailbox_ref: ref}, %{"email" => email}) do
        {:ok, _} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end
  end

  defp email(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    if Mailboxes.valid_email?(normalized), do: {:ok, normalized}, else: {:error, :invalid_email}
  end

  defp email(_), do: {:error, :invalid_email}

  defp fresh!(scope, ref), do: Access.lock!(scope, ref)

  defp insert!(changeset) do
    case Repo.insert(changeset) do
      {:ok, draft} -> draft
      {:error, error} -> Repo.rollback(error)
    end
  end

  defp positive(value, fallback) do
    case Integer.parse(to_string(value || "")) do
      {n, ""} when n > 0 -> n
      _ -> fallback
    end
  end
end
