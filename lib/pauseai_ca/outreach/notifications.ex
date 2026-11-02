defmodule PauseAiCa.Outreach.Notifications do
  @moduledoc "Durable, idempotent reply notification outbox. Unknown submissions require reconciliation."
  import Ecto.Query
  alias PauseAiCa.{Repo, Accounts}
  alias PauseAiCa.Outreach.{Notification, Mailboxes}
  alias PhoenixCRM.Conversations

  def enqueue!(message, conversation, mailbox) do
    latest = Conversations.latest_submission(Repo, mailbox.id, conversation.id)

    candidates =
      if latest,
        do: [%{direction: latest.direction, state: latest.outcome, actor_id: latest.actor_id}],
        else: []

    recipient = PhoenixMailWorkflow.Outreach.notification_recipient(candidates, mailbox.owner_id)

    user =
      Mailboxes.authorized_actor(recipient, mailbox.id) ||
        Mailboxes.authorized_actor(mailbox.owner_id, mailbox.id)

    Repo.insert!(
      %Notification{
        message_id: message.id,
        conversation_id: conversation.id,
        mailbox_ref: mailbox.id,
        recipient_actor_id: if(user, do: user.id),
        state: if(user, do: "pending", else: "unassigned")
      },
      on_conflict: :nothing,
      conflict_target: :message_id
    )
  end

  def pending(limit) do
    Repo.all(
      from(n in Notification,
        where: n.state == "pending",
        order_by: [asc: n.inserted_at, asc: n.id],
        limit: ^min(max(limit, 1), 100)
      )
    )
  end

  def status(scope) do
    if PauseAiCa.Outreach.access?(scope) do
      {:ok, boxes} = Mailboxes.all(scope)
      refs = Enum.map(boxes, & &1.id)

      {:ok,
       Repo.all(
         from(n in Notification,
           where: n.mailbox_ref in ^refs,
           order_by: [desc: n.updated_at, desc: n.id],
           limit: 100
         )
       )}
    else
      {:error, :unauthorized}
    end
  end

  def dispatch(adapter) when is_function(adapter, 1) do
    Enum.map(pending(25), fn notification ->
      case reserve(notification.id) do
        {:ok, {:send, notification, user, mailbox}} ->
          submit(adapter, notification, user, mailbox)

        other ->
          other
      end
    end)
  end

  defp reserve(id) do
    Repo.transaction(fn ->
      row = Repo.one(from(n in Notification, where: n.id == ^id, lock: "FOR UPDATE"))
      if is_nil(row) or row.state != "pending", do: Repo.rollback(:not_pending)
      mailbox = Enum.find(Mailboxes.configured(), &(&1.id == row.mailbox_ref))

      user =
        Mailboxes.authorized_actor(row.recipient_actor_id, row.mailbox_ref) ||
          (mailbox && Mailboxes.authorized_actor(mailbox.owner_id, row.mailbox_ref))

      cond do
        is_nil(mailbox) or not mailbox.enabled? or not mailbox.verified? ->
          Repo.update!(Ecto.Changeset.change(row, state: "blocked", error: "mailbox_unavailable"))

        is_nil(user) ->
          Repo.update!(
            Ecto.Changeset.change(row, state: "blocked", error: "recipient_unauthorized")
          )

        true ->
          reserved =
            Repo.update!(
              Ecto.Changeset.change(row,
                state: "reserved",
                recipient_actor_id: user.id,
                attempted_at: DateTime.utc_now()
              )
            )

          {:send, reserved, user, mailbox}
      end
    end)
  end

  defp submit(adapter, notification, user, mailbox) do
    result =
      try do
        Repo.transaction(fn ->
          user = Repo.one!(from(u in Accounts.User, where: u.id == ^user.id, lock: "FOR UPDATE"))
          scope = Accounts.Scope.for_user(user)
          PauseAiCa.Outreach.Access.lock!(scope, mailbox.id)

          case Mailboxes.sending(scope, mailbox.id) do
            {:ok, current} ->
              conversation = Conversations.get(Repo, current.id, notification.conversation_id)

              message =
                Repo.get_by(PhoenixCRM.Message,
                  id: notification.message_id,
                  conversation_id: conversation.id,
                  mailbox_ref: current.id
                )

              adapter.(%{
                notification: notification,
                user: user,
                conversation: conversation,
                mailbox: current,
                message: message
              })

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)
      rescue
        _ -> {:error, :notification_exception}
      catch
        _, _ -> {:error, :notification_exception}
      end

    {state, error} =
      case result do
        {:ok, {:ok, _metadata}} ->
          {"accepted", nil}

        {:error, reason} when reason in [:unauthorized, :mailbox_unavailable] ->
          {"blocked", to_string(reason)}

        _ ->
          {"unknown", "Acceptance uncertain; reconcile before retrying."}
      end

    Repo.update(
      Ecto.Changeset.change(notification,
        state: state,
        error: error,
        accepted_at: if(state == "accepted", do: DateTime.utc_now())
      )
    )
  end
end
