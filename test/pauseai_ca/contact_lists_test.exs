defmodule PauseAiCa.ContactListsTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, ContactLists, CRM, Repo}
  alias PauseAiCa.Accounts.Scope
  alias PhoenixCRM.{Address, MailingListEvent, MailingLists, Person}

  setup do
    actor = user_fixture() |> change(superadmin: true) |> Repo.update!()
    %{actor: actor, scope: Scope.for_user(actor)}
  end

  test "static membership resolves canonical aliases and revisions protect additions, archive and restore",
       c do
    person = Repo.insert!(%Person{name: "Synthetic canonical"})
    alias_person = Repo.insert!(%Person{name: "Synthetic alias", canonical_id: person.id})

    assert {:ok, list} =
             ContactLists.save(c.scope, nil, %{"name" => "Static selection", "kind" => "static"})

    assert list.criteria == %{"kind" => "static", "person_ids" => []}

    assert {:ok, added} =
             ContactLists.add_members(
               c.scope,
               list.id,
               [alias_person.id, person.id],
               list.revision
             )

    assert added.criteria["person_ids"] == [person.id]

    assert {:error, :stale} =
             ContactLists.add_members(c.scope, list.id, [person.id], list.revision)

    assert {:ok, [id]} = CRM.directory_ids(c.scope, %{"saved_filter_id" => list.id})
    assert id == person.id

    assert {:ok, %{records: [%{person: %{id: ^id}}]}} =
             ContactLists.members_page(c.scope, list.id)

    assert {:ok, archived} = ContactLists.archive(c.scope, added)
    assert {:ok, []} = ContactLists.list(c.scope)
    assert {:ok, [stored]} = ContactLists.list(c.scope, true)
    assert stored.id == list.id
    assert {:error, :archived} = ContactLists.prepare_for_list_email(c.scope, list.id)
    assert {:ok, restored} = ContactLists.restore(c.scope, archived)
    assert restored.archived_at == nil
    assert restored.criteria == added.criteria

    assert Enum.map(Repo.all(from e in MailingListEvent, order_by: e.revision), & &1.action) == [
             "created",
             "updated",
             "archived",
             "restored"
           ]

    assert Repo.all(MailingListEvent) |> Enum.all?(&(&1.actor_id == c.actor.id))

    assert {:ok, emptied} =
             ContactLists.remove_members(
               c.scope,
               restored.id,
               [alias_person.id],
               restored.revision
             )

    assert emptied.criteria["person_ids"] == []
    assert {:ok, []} = CRM.directory_ids(c.scope, %{"saved_filter_id" => restored.id})

    assert {:error, :kind_change_requires_review} =
             ContactLists.save(c.scope, emptied, %{
               "name" => "Changed",
               "kind" => "dynamic",
               "city" => "Toronto"
             })
  end

  test "saved static aliases follow merges and dynamic manual exclusions win", c do
    target = Repo.insert!(%Person{name: "Target", city: "Toronto"})
    old = Repo.insert!(%Person{name: "Old identity"})
    extra = Repo.insert!(%Person{name: "Manual member", city: "Ottawa"})

    assert {:ok, static} =
             MailingLists.create(CRM.context(), c.scope, %{
               name: "Before merge",
               criteria: %{"kind" => "static", "person_ids" => [old.id]}
             })

    old |> change(canonical_id: target.id) |> Repo.update!()
    assert {:ok, [id]} = CRM.directory_ids(c.scope, %{"saved_filter_id" => static.id})
    assert id == target.id

    criteria = %{
      "match" => "any",
      "rules" => [%{"field" => "city", "operator" => "equals", "values" => ["Toronto"]}],
      "include_ids" => [extra.id],
      "exclude_ids" => [target.id]
    }

    assert {:ok, dynamic} =
             MailingLists.create(CRM.context(), c.scope, %{
               name: "Manual geography",
               criteria: criteria
             })

    assert {:ok, ids} = CRM.directory_ids(c.scope, %{"saved_filter_id" => dynamic.id})
    assert ids == [extra.id]

    assert {:ok, updated} =
             ContactLists.add_members(c.scope, dynamic.id, [target.id], dynamic.revision)

    assert target.id in updated.criteria["include_ids"]
    assert updated.criteria["exclude_ids"] == []
    assert {:ok, ids} = CRM.directory_ids(c.scope, %{"saved_filter_id" => dynamic.id})
    assert Enum.sort(ids) == Enum.sort([target.id, extra.id])

    assert {:ok, removed} =
             ContactLists.remove_members(c.scope, dynamic.id, [extra.id], updated.revision)

    assert removed.criteria["exclude_ids"] == [extra.id]
    assert {:ok, [id]} = CRM.directory_ids(c.scope, %{"saved_filter_id" => dynamic.id})
    assert id == target.id

    assert {:error, :stale} =
             ContactLists.remove_members(c.scope, dynamic.id, [target.id], updated.revision)
  end

  test "accounts reuse existing canonical email identities and observe missing identities without granting roles or consent",
       c do
    existing_user = user_fixture()
    missing_user = user_fixture()
    person = Repo.insert!(%Person{name: "Canonical account contact"})
    alias_person = Repo.insert!(%Person{name: "Old account contact", canonical_id: person.id})
    Repo.insert!(%Address{person_id: alias_person.id, email: existing_user.email})
    users_before = Repo.aggregate(Accounts.User, :count)
    assert {:ok, ids} = ContactLists.account_people(c.scope, [existing_user.id, missing_user.id])
    assert person.id in ids
    assert length(ids) == 2
    assert {:ok, ^ids} = ContactLists.account_people(c.scope, [existing_user.id, missing_user.id])
    assert Repo.aggregate(Person, :count) == 3
    assert Repo.aggregate(Accounts.User, :count) == users_before
    assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
    assert Repo.aggregate(PauseAiCa.Volunteers.Manager, :count) == 0
    refute Repo.reload!(missing_user).superadmin

    assert {:error, :unauthorized} =
             ContactLists.account_people(Scope.for_user(existing_user), [missing_user.id])
  end

  test "email preparation retains excluded identities for review and failure leaves no empty draft",
       c do
    no_address = Repo.insert!(%Person{name: "Addressless identity"})
    assert {:error, :audience_required} = ContactLists.prepare_email(c.scope, [no_address.id])
    assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == 0
    addressed = Repo.insert!(%Person{name: "Addressed identity"})
    Repo.insert!(%Address{person_id: addressed.id, email: "selected@example.org"})
    assert {:ok, draft} = ContactLists.prepare_email(c.scope, [addressed.id, no_address.id])
    assert draft.recipient_mode == "contacts"
    assert Enum.sort(draft.recipient_keys) == Enum.sort([addressed.id, no_address.id])
    assert Repo.aggregate(PauseAiCa.Newsletters.Batch, :count) == 0
    assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
    c.actor |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = ContactLists.prepare_email(c.scope, [addressed.id])

    assert {:error, :unauthorized} =
             ContactLists.save(c.scope, nil, %{"name" => "Denied", "kind" => "static"})

    assert Repo.aggregate(PauseAiCa.Newsletters.Draft, :count) == 1
  end

  test "draft edition uses verified contact language consensus and mixed evidence stays unknown",
       c do
    people =
      for {email, language} <- [
            {"english-one@example.org", "en"},
            {"english-two@example.org", "en"}
          ] do
        person = Repo.insert!(%Person{name: "Synthetic language contact"})
        Repo.insert!(%Address{person_id: person.id, email: email})

        assert {:ok, _} =
                 PauseAiCa.Newsletters.Edition.confirm_preference(c.scope, email, language)

        person
      end

    ids = Enum.map(people, & &1.id)
    assert {:ok, english} = ContactLists.prepare_email(c.scope, ids)
    assert english.edition == "en"

    assert {:ok, _} =
             PauseAiCa.Newsletters.Edition.confirm_preference(
               c.scope,
               "english-two@example.org",
               "fr"
             )

    assert {:ok, mixed} = ContactLists.prepare_email(c.scope, ids)
    assert mixed.edition == "unknown"
    assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
  end
end
