defmodule PauseAiCa.ContactLists do
  @moduledoc "Consumer-owned contact list editing and explicit recipient snapshots. Membership grants no consent or account authority."
  import Ecto.Query
  alias PauseAiCa.{AccountManagement, CRM, Repo, Volunteers}
  alias PauseAiCa.Accounts.User
  alias PauseAiCa.Newsletters.{Batches, Drafts}
  alias PhoenixCRM.{Address, AreaRules, ListRules, MailingList, MailingLists, Person}
  @maximum 5000

  def list(scope, archived? \\ false),
    do: MailingLists.list(CRM.context(), scope, archived: archived?)

  def get(scope, id), do: MailingLists.get(CRM.context(), scope, id)

  def form(nil), do: Map.merge(AreaRules.form(nil), %{"name" => "", "kind" => "dynamic"})

  def form(list),
    do:
      Map.merge(AreaRules.form(list.criteria), %{
        "name" => list.name,
        "kind" => kind(list.criteria)
      })

  def save(scope, expected, attrs) do
    write(scope, fn ->
      current = result!(current_expected(scope, expected))

      if current && kind(current.criteria) != attrs["kind"],
        do: Repo.rollback(:kind_change_requires_review)

      criteria = result!(edited_criteria(scope, current, attrs))
      values = %{name: attrs["name"], criteria: criteria}

      result!(
        if current,
          do: MailingLists.save(CRM.context(), scope, current, values),
          else: MailingLists.create(CRM.context(), scope, values)
      )
    end)
  end

  def archive(scope, %MailingList{} = expected),
    do:
      write(scope, fn ->
        MailingLists.archive(CRM.context(), scope, result!(current_expected(scope, expected)))
        |> result!()
      end)

  def archive(_, _), do: {:error, :invalid_list}

  def restore(scope, %MailingList{} = expected),
    do:
      write(scope, fn ->
        MailingLists.restore(CRM.context(), scope, result!(current_expected(scope, expected)))
        |> result!()
      end)

  def restore(_, _), do: {:error, :invalid_list}

  def add_members(scope, id, person_ids, expected_revision),
    do: change_members(scope, id, person_ids, expected_revision, :add)

  def remove_members(scope, id, person_ids, expected_revision),
    do: change_members(scope, id, person_ids, expected_revision, :remove)

  defp change_members(scope, id, person_ids, expected_revision, action) do
    write(scope, fn ->
      list = result!(get(scope, id))
      if list.revision != expected_revision, do: Repo.rollback(:stale)
      ids = result!(canonical_ids(scope, person_ids))
      criteria = result!(canonical_criteria(scope, list.criteria))
      criteria = result!(ListRules.normalize_criteria(membership_criteria(criteria, ids, action)))
      result!(MailingLists.save(CRM.context(), scope, list, %{criteria: criteria}))
    end)
  end

  defp membership_criteria(%{"kind" => "static"} = criteria, ids, :add),
    do: Map.update!(criteria, "person_ids", &Enum.uniq(&1 ++ ids))

  defp membership_criteria(%{"kind" => "static"} = criteria, ids, :remove),
    do: Map.update!(criteria, "person_ids", &(&1 -- ids))

  defp membership_criteria(criteria, ids, :add) do
    criteria
    |> Map.update("include_ids", ids, &Enum.uniq(&1 ++ ids))
    |> Map.update("exclude_ids", [], &(&1 -- ids))
  end

  defp membership_criteria(criteria, ids, :remove) do
    criteria
    |> Map.update("exclude_ids", ids, &Enum.uniq(&1 ++ ids))
    |> Map.update("include_ids", [], &(&1 -- ids))
  end

  @doc "Resolve selected existing aliases and canonical people in one batched identity query."
  def canonical_ids(scope, ids) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, ids} <- validated_ids(ids),
         {:ok, mapping} <- canonical_mapping(ids),
         true <- Volunteers.superadmin?(scope) do
      {:ok, ids |> Enum.map(&Map.fetch!(mapping, &1)) |> Enum.uniq()}
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc "Read-only canonical projection of every static/manual membership field, preserving exclusions."
  def canonical_criteria(scope, criteria) do
    with true <- Volunteers.superadmin?(scope),
         {:ok, criteria} <- ListRules.normalize_criteria(criteria),
         {:ok, mapping} <-
           canonical_mapping(
             Enum.flat_map(~w(person_ids include_ids exclude_ids), &Map.get(criteria, &1, []))
           ),
         true <- Volunteers.superadmin?(scope) do
      {:ok,
       Enum.reduce(~w(person_ids include_ids exclude_ids), criteria, fn key, result ->
         if Map.has_key?(result, key),
           do:
             Map.update!(result, key, fn ids ->
               ids |> Enum.map(&Map.fetch!(mapping, &1)) |> Enum.uniq()
             end),
           else: result
       end)}
    else
      false -> {:error, :unauthorized}
      error -> error
    end
  end

  @doc "Resolve freshly scoped account selections through existing email identities, observing only missing contacts."
  def account_people(scope, user_ids) do
    write(scope, fn ->
      ids = result!(validated_ids(user_ids))
      allowed = AccountManagement.selected_matching_ids(scope, "", ids)
      if Enum.sort(allowed) != Enum.sort(ids), do: Repo.rollback(:unauthorized)
      users = Repo.all(from u in User, where: u.id in ^ids, order_by: u.id)
      emails = Enum.map(users, &String.downcase(&1.email))

      existing =
        Repo.all(
          from a in Address,
            join: p in Person,
            on: p.id == a.person_id,
            join: canonical in Person,
            on: canonical.id == p.id or canonical.id == p.canonical_id,
            where: a.email in ^emails and is_nil(canonical.canonical_id),
            select: {a.email, canonical.id}
        )
        |> Map.new()

      Enum.map(users, fn user ->
        case Map.fetch(existing, String.downcase(user.email)) do
          {:ok, id} ->
            id

          :error ->
            record =
              result!(
                CRM.observe(
                  scope,
                  %{"email" => user.email, "name" => user.name, "city" => user.city},
                  "website_account",
                  user.id
                )
              )

            record.person.id
        end
      end)
      |> Enum.uniq()
    end)
  end

  @doc "Create and populate one unsent contact draft atomically. Excluded recipients remain visible for review."
  def prepare_email(scope, person_ids) do
    write(scope, fn ->
      ids = result!(canonical_ids(scope, person_ids))
      rows = result!(Batches.contact_recipients(scope, ids))
      unless Enum.any?(rows, &(&1.status == :available)), do: Repo.rollback(:audience_required)
      draft = result!(Drafts.create(scope))

      result!(
        Drafts.save(scope, draft, %{
          "recipient_mode" => "contacts",
          "recipient_keys" => ids,
          "edition" => consensus_edition(rows)
        })
      )
    end)
  end

  defp consensus_edition(rows) do
    case Enum.uniq(Enum.map(rows, &Map.get(&1, :edition, "unknown"))) do
      [language] when language in ["en", "fr"] -> language
      _ -> "unknown"
    end
  end

  def members_page(scope, id, params \\ %{}) do
    with {:ok, _} <- active_list(scope, id),
         do: CRM.directory_page(scope, Map.put(params, "saved_filter_id", id))
  end

  def prepare_for_list_email(scope, id) do
    with {:ok, _} <- active_list(scope, id),
         {:ok, ids} <- CRM.directory_ids(scope, %{"saved_filter_id" => id}),
         do: prepare_email(scope, ids)
  end

  defp active_list(scope, id) do
    case get(scope, id) do
      {:ok, %{archived_at: nil} = list} -> {:ok, list}
      {:ok, _} -> {:error, :archived}
      error -> error
    end
  end

  defp current_expected(_scope, nil), do: {:ok, nil}

  defp current_expected(scope, %MailingList{} = expected) do
    with {:ok, current} <- get(scope, expected.id) do
      if current.revision == expected.revision, do: {:ok, current}, else: {:error, :stale}
    end
  end

  defp current_expected(_, _), do: {:error, :invalid_list}

  defp edited_criteria(scope, current, %{"kind" => "static"}) do
    ids =
      case current do
        nil -> {:ok, []}
        %{criteria: %{"kind" => "static", "person_ids" => ids}} -> canonical_ids(scope, ids)
        _ -> {:error, :kind_change_requires_review}
      end

    with {:ok, ids} <- ids, do: {:ok, %{"kind" => "static", "person_ids" => ids}}
  end

  defp edited_criteria(scope, current, %{"kind" => "dynamic"} = attrs) do
    with {:ok, geography} <-
           AreaRules.criteria(attrs,
             normalize_postal: &PauseAiCa.PostalArea.normalize/1,
             valid_postal?: &PauseAiCa.PostalArea.valid?/1
           ),
         {:ok, previous} <- previous_criteria(scope, current) do
      ListRules.normalize_criteria(
        Map.merge(geography, Map.take(previous, ~w(include_ids exclude_ids)))
      )
    end
  end

  defp edited_criteria(_, _, _), do: {:error, :invalid_kind}

  defp previous_criteria(_scope, nil), do: {:ok, %{}}
  defp previous_criteria(scope, current), do: canonical_criteria(scope, current.criteria)
  defp kind(%{"kind" => "static"}), do: "static"
  defp kind(_), do: "dynamic"

  defp validated_ids(ids) when is_list(ids) and length(ids) <= @maximum do
    cast = Enum.map(ids, &Ecto.UUID.cast/1)

    if Enum.all?(cast, &match?({:ok, _}, &1)),
      do: {:ok, cast |> Enum.map(&elem(&1, 1)) |> Enum.uniq()},
      else: {:error, :invalid_selection}
  end

  defp validated_ids(_), do: {:error, :invalid_selection}

  defp canonical_mapping(ids) do
    ids = Enum.uniq(ids)

    mapping =
      Repo.all(
        from p in Person,
          join: canonical in Person,
          on: canonical.id == p.id or canonical.id == p.canonical_id,
          where: p.id in ^ids and is_nil(canonical.canonical_id),
          select: {p.id, canonical.id}
      )
      |> Map.new()

    if map_size(mapping) == length(ids), do: {:ok, mapping}, else: {:error, :invalid_selection}
  end

  defp write(scope, fun) do
    if Volunteers.superadmin?(scope) do
      Repo.transaction(fn ->
        actor = Repo.one(from u in User, where: u.id == ^scope.user.id, lock: "FOR UPDATE")
        unless actor && actor.superadmin && actor.confirmed_at, do: Repo.rollback(:unauthorized)
        result = fun.()
        unless Volunteers.superadmin?(scope), do: Repo.rollback(:unauthorized)
        result
      end)
    else
      {:error, :unauthorized}
    end
  end

  defp result!({:ok, result}), do: result
  defp result!({:error, reason}), do: Repo.rollback(reason)
end
