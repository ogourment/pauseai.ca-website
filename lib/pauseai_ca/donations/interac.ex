defmodule PauseAiCa.Donations.Interac do
  @moduledoc "Consumer-owned scope, rate limits and private bank reconciliation for Interac declarations."
  import Ecto.Query
  alias PauseAiCa.{Accounts, Repo, Volunteers}
  alias PauseAiCa.Donations.InteracDeclaration
  alias PhoenixDonations.Declarations

  def change(scope, attrs \\ %{}) do
    # Presentation only. Submission always rebuilds the shared insert-only changeset.
    %{Declarations.change(InteracDeclaration, attrs, trusted_options(scope, attrs)) | action: nil}
  end

  def submit(scope, attrs, submission_key) when is_binary(submission_key) do
    if (attrs["website"] || "") != "",
      do: {:ok, :recorded},
      else: persist_submission(scope, attrs, submission_key)
  end

  defp persist_submission(scope, attrs, submission_key) do
    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock(hashtext('interac-declaration-submit'))")
      options = trusted_options(scope, attrs) |> Keyword.put(:submission_key, submission_key)
      changeset = Declarations.change(InteracDeclaration, attrs, options)
      if not changeset.valid?, do: Repo.rollback(%{changeset | action: :insert})
      email = Ecto.Changeset.get_field(changeset, :email)
      since = DateTime.add(DateTime.utc_now(), -3600)

      replay =
        Repo.exists?(from d in InteracDeclaration, where: d.submission_key == ^submission_key)

      if not replay and
           (Repo.aggregate(from(d in InteracDeclaration, where: d.inserted_at >= ^since), :count) >=
              200 or
              Repo.aggregate(
                from(d in InteracDeclaration,
                  where: d.email == ^email and d.inserted_at >= ^since
                ),
                :count
              ) >= 5),
         do: Repo.rollback(:rate_limited)

      case Declarations.submit(Repo, InteracDeclaration, attrs, options) do
        {:ok, declaration} -> declaration
        {:error, error} -> Repo.rollback(error)
      end
    end)
  end

  def list(scope, page \\ 1) do
    if Volunteers.superadmin?(scope) do
      rows =
        Repo.all(
          from d in InteracDeclaration,
            order_by: [desc: d.inserted_at, desc: d.id],
            limit: 26,
            offset: ^((max(page, 1) - 1) * 25)
        )

      if Volunteers.superadmin?(scope), do: {:ok, rows}, else: {:error, :unauthorized}
    else
      {:error, :unauthorized}
    end
  end

  def summary(scope) do
    if Volunteers.superadmin?(scope) do
      counts =
        Repo.all(from d in InteracDeclaration, group_by: d.state, select: {d.state, count(d.id)})
        |> Map.new()

      received =
        Repo.one(
          from d in InteracDeclaration,
            where: d.state == "verified",
            select: fragment("COALESCE(SUM(?), 0)::bigint", d.received_minor)
        )

      if Volunteers.superadmin?(scope),
        do:
          {:ok,
           %{
             pending: Map.get(counts, "pending", 0),
             verified: Map.get(counts, "verified", 0),
             received_minor: received
           }},
        else: {:error, :unauthorized}
    else
      {:error, :unauthorized}
    end
  end

  def get(scope, id) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, uuid} <- Ecto.UUID.cast(id),
         %InteracDeclaration{} = declaration <- Repo.get(InteracDeclaration, uuid),
         true <- Volunteers.superadmin?(scope) do
      {:ok, declaration}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def verify(scope, id, attrs, expected_revision) do
    if Volunteers.superadmin?(scope) do
      Repo.transaction(fn ->
        actor =
          Repo.one(from u in Accounts.User, where: u.id == ^scope.user.id, lock: "FOR UPDATE")

        if is_nil(actor) or not Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)
        attrs = normalize_reference(attrs)

        case Declarations.verify(Repo, InteracDeclaration, id, attrs,
               source_ref: "interac",
               expected_revision: expected_revision,
               actor_id: actor.id
             ) do
          {:ok, declaration} -> declaration
          {:error, error} -> Repo.rollback(error)
        end
      end)
    else
      {:error, :unauthorized}
    end
  end

  defp trusted_options(scope, attrs) do
    user =
      case scope do
        %{user: %{id: id}} -> Repo.get(Accounts.User, id)
        _ -> nil
      end

    if user do
      [
        currency: "CAD",
        account_ref: user.id,
        account_email: user.email,
        account_name:
          if(Map.has_key?(attrs, "name") or Map.has_key?(attrs, :name), do: nil, else: user.name),
        actor_id: user.id
      ]
    else
      [currency: "CAD", actor_id: "public"]
    end
  end

  defp normalize_reference(attrs) do
    reference = attrs["bank_reference"]

    if is_binary(reference),
      do: Map.put(attrs, "bank_reference", reference |> String.trim() |> String.upcase()),
      else: attrs
  end
end
