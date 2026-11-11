defmodule PauseAiCa.Newsletters.Drafts do
  @moduledoc "Private author drafts with fresh superadmin checks, reversible archive and optimistic revisions."
  import Ecto.Query
  alias PauseAiCa.{Repo, Volunteers, Accounts.User}
  alias PauseAiCa.Newsletters.Draft
  alias PauseAiCa.Outreach.{Access, Mailboxes}

  def list(scope, archived? \\ false, workspace \\ "") do
    if Volunteers.superadmin?(scope) or Access.eligible?(scope) do
      query =
        from(d in Draft,
          where: d.owner_id == ^scope.user.id,
          order_by: [desc: d.updated_at, desc: d.id]
        )

      query =
        if Volunteers.superadmin?(scope) do
          query
        else
          {:ok, boxes} = Mailboxes.all(scope)
          refs = Enum.map(boxes, & &1.id)

          from(d in query,
            where: d.recipient_mode == "outreach" and d.outreach_mailbox_ref in ^refs
          )
        end

      query =
        if archived?,
          do: from(d in query, where: not is_nil(d.archived_at)),
          else: from(d in query, where: is_nil(d.archived_at))

      case workspace_query(query, workspace) do
        {:ok, query} -> {:ok, Repo.all(query)}
        error -> error
      end
    else
      {:error, :unauthorized}
    end
  end

  defp workspace_query(query, ""), do: {:ok, query}

  defp workspace_query(query, "emails"),
    do: {:ok, from(d in query, where: d.recipient_mode in ["contacts", "outreach"])}

  defp workspace_query(query, "newsletters"),
    do: {:ok, from(d in query, where: d.recipient_mode in ["newsletter", "list"])}

  defp workspace_query(_, _), do: {:error, :invalid_workspace}

  def get(scope, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Draft{} = draft <-
           Repo.one(from(d in Draft, where: d.id == ^uuid and d.owner_id == ^scope.user.id)),
         true <- readable?(scope, draft) do
      {:ok, draft}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def create(scope, workspace \\ "")

  def create(scope, workspace) when workspace in ["", "emails", "newsletters"] do
    mode = if workspace == "emails", do: "contacts", else: "newsletter"

    authorized(scope, fn ->
      Repo.insert!(%Draft{owner_id: scope.user.id, recipient_mode: mode})
    end)
  end

  def create(_, _), do: {:error, :invalid_workspace}

  def create_account_invitations(scope, person_ids, attrs) do
    authorized(scope, fn ->
      rows =
        case PauseAiCa.Newsletters.Batches.contact_recipients(scope, person_ids) do
          {:ok, rows} -> rows
          {:error, reason} -> Repo.rollback(reason)
        end

      if attrs["language"] in ["en", "fr"] do
        Enum.each(Enum.filter(rows, &(&1.status == :available)), fn row ->
          case PauseAiCa.Newsletters.Edition.confirm_preference(
                 scope,
                 row.email,
                 attrs["language"]
               ) do
            {:ok, _} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
      end

      plan =
        case PhoenixMailWorkflow.Invitations.plan(
               rows,
               attrs,
               &PauseAiCa.Mail.AccountInvitation.content/2
             ) do
          {:ok, plan} -> plan
          {:error, reason} -> Repo.rollback(reason)
        end

      drafts =
        for planned <- plan.drafts do
          %Draft{owner_id: scope.user.id}
          |> Draft.changeset(
            Map.merge(planned.content, %{
              "edition" => planned.edition,
              "recipient_mode" => "contacts",
              "recipient_keys" => planned.recipient_ids
            })
          )
          |> Repo.insert!()
        end

      %{drafts: drafts, included: plan.included, excluded: plan.excluded}
    end)
  end

  def create_for_list(scope, list_id) do
    authorized(scope, fn ->
      case PauseAiCa.Newsletters.Lists.get(scope, list_id) do
        {:ok, %{archived_at: nil} = list} ->
          Repo.insert!(%Draft{
            owner_id: scope.user.id,
            recipient_mode: "list",
            mailing_list_id: list.id
          })

        _ ->
          Repo.rollback(:audience_required)
      end
    end)
  end

  def create_edition(scope, %Draft{} = expected, edition)
      when edition in ["en", "fr", "unknown"] do
    with {:ok, current} <- get(scope, expected.id) do
      authorized(scope, fn ->
        Repo.insert!(%Draft{
          owner_id: scope.user.id,
          edition: edition,
          recipient_mode: current.recipient_mode,
          recipient_keys: [],
          mailing_list_id: current.mailing_list_id,
          region: current.region
        })
      end)
    end
  end

  def create_edition(_, _, _), do: {:error, :invalid_edition}

  def save(scope, %Draft{} = expected, attrs) do
    authorized(
      scope,
      fn ->
        draft = locked(scope, expected)
        if draft.archived_at, do: Repo.rollback(:archived)
        changeset = draft |> Draft.changeset(attrs)
        changeset = PauseAiCa.Outreach.validate_changes(scope, draft, changeset)

        changeset =
          if Ecto.Changeset.get_field(changeset, :recipient_mode) == "list" do
            case PauseAiCa.Newsletters.Lists.get(
                   scope,
                   Ecto.Changeset.get_field(changeset, :mailing_list_id)
                 ) do
              {:ok, %{archived_at: nil}} -> changeset
              _ -> Ecto.Changeset.add_error(changeset, :mailing_list_id, "is invalid")
            end
          else
            Ecto.Changeset.put_change(changeset, :mailing_list_id, nil)
          end

        changeset = changeset |> Ecto.Changeset.optimistic_lock(:revision)

        case Repo.update(changeset) do
          {:ok, saved} -> saved
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end,
      expected
    )
  end

  def archive(scope, %Draft{} = expected, archive? \\ true) do
    authorized(
      scope,
      fn ->
        locked(scope, expected)
        |> Ecto.Changeset.change(archived_at: if(archive?, do: DateTime.utc_now(), else: nil))
        |> Ecto.Changeset.optimistic_lock(:revision)
        |> Repo.update!()
      end,
      expected
    )
  end

  defp locked(scope, expected) do
    draft =
      Repo.one(
        from(d in Draft,
          where: d.id == ^expected.id and d.owner_id == ^scope.user.id,
          lock: "FOR UPDATE"
        )
      )

    if is_nil(draft), do: Repo.rollback(:unauthorized)
    if not readable?(scope, draft), do: Repo.rollback(:unauthorized)
    if draft.outreach_mailbox_ref, do: Access.lock!(scope, draft.outreach_mailbox_ref)
    if draft.revision != expected.revision, do: Repo.rollback(:stale)
    draft
  end

  defp authorized(scope, fun, expected \\ nil) do
    if authorizer?(scope, expected) do
      Repo.transaction(fn ->
        Repo.one(from(u in User, where: u.id == ^scope.user.id, lock: "FOR UPDATE"))
        if not authorizer?(scope, expected), do: Repo.rollback(:unauthorized)
        fun.()
      end)
    else
      {:error, :unauthorized}
    end
  end

  defp authorizer?(scope, %Draft{}), do: Volunteers.superadmin?(scope) or Access.eligible?(scope)
  defp authorizer?(scope, _), do: Volunteers.superadmin?(scope)

  defp readable?(scope, draft) do
    Volunteers.superadmin?(scope) or
      (draft.recipient_mode == "outreach" and is_binary(draft.outreach_mailbox_ref) and
         match?({:ok, _}, Mailboxes.fetch(scope, draft.outreach_mailbox_ref)))
  end
end
