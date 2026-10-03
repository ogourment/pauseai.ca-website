defmodule PauseAiCa.MailTest do
  use PauseAiCa.DataCase
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Mail, CRM, Volunteers}
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.ContactMigration.Contact

  setup do
    admin =
      user_fixture()
      |> Ecto.Changeset.change(superadmin: true, confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    scope = Scope.for_user(admin)
    {:ok, group} = Volunteers.create_group(scope, %{"name" => "Montréal"})

    member =
      user_fixture(%{email: "mail-member@example.org"})
      |> Ecto.Changeset.change(
        name: "Camille",
        city: "Montréal",
        confirmed_at: DateTime.utc_now(:second),
        organizing_group_id: group.id
      )
      |> Repo.update!()

    %{admin: admin, scope: scope, member: member}
  end

  test "drafts are private, optimistic edits cannot overwrite each other, repeat generation preserves edits",
       c do
    {:ok, batch} = Mail.create(c.scope, c.member.id)

    {:ok, batch} =
      Mail.save_batch(c.scope, batch, %{
        "subject" => "Hello {{name}}",
        "source" => "Meet in {{city}}"
      })

    assert {:error, :stale} =
             Mail.save_batch(c.scope, %{batch | revision: batch.revision - 1}, %{
               "subject" => "Stale"
             })

    {:ok, [draft]} = Mail.generate(c.scope, batch.id)
    assert draft.subject == "Hello Camille"
    assert draft.variables["city"] == "Montréal"
    {:ok, edited} = Mail.save_draft(c.scope, draft, %{"source" => "Personal edit"})
    assert {:error, :stale} = Mail.save_draft(c.scope, draft, %{"source" => "Old browser"})
    {:ok, [repeat]} = Mail.generate(c.scope, batch.id)
    assert repeat.id == edited.id
    assert repeat.source == "Personal edit"

    another =
      user_fixture()
      |> Ecto.Changeset.change(superadmin: true, confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    assert {:error, :unauthorized} = Mail.get(Scope.for_user(another), batch.id)
    assert Mail.list(Scope.for_user(another)) == []
  end

  test "one missing variable rolls back the entire generation", c do
    incomplete =
      user_fixture()
      |> Ecto.Changeset.change(name: "René", confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    {:ok, batch} = Mail.create(c.scope, c.member.id)

    {:ok, batch} =
      Mail.save_batch(c.scope, batch, %{
        "recipient_ids" => [c.member.id, incomplete.id],
        "subject" => "Hello",
        "source" => "Meet in {{city}}"
      })

    assert {:error, {:missing_variables, ["city"]}} = Mail.generate(c.scope, batch.id)
    assert Repo.aggregate(Mail.Draft, :count) == 0
  end

  test "withdrawal on a merged origin denies all addresses without changing accounts", c do
    {:ok, a} = CRM.observe(c.scope, %{"email" => c.member.email}, "sheet", "1")

    contact =
      Repo.insert!(
        Contact.changeset(%Contact{}, %{
          email: "withdrawn@example.org",
          source: "review",
          classification: "do_not_contact"
        })
      )

    {:ok, link} = CRM.link_contact(c.scope, contact)
    {:ok, comparison} = CRM.compare(c.scope, a.person.id, link.person_id)
    {:ok, _} = CRM.merge(c.scope, comparison, %{"preferred_address_id" => hd(a.addresses).id})
    assert {:error, :ineligible} = Mail.recipient(c.scope, c.member.id)
    assert Repo.get!(PauseAiCa.Accounts.User, c.member.id).email == c.member.email
  end

  test "historical import and old links retain human corrections and immutable sources", c do
    contact =
      Repo.insert!(
        Contact.changeset(%Contact{}, %{
          email: "legacy@example.org",
          name: "Source name",
          city: "Québec",
          source: "sheet",
          source_key: "row-1"
        })
      )

    {:ok, link} = CRM.link_contact(c.scope, contact)
    {:ok, record} = CRM.get(c.scope, link.person_id)
    {:ok, _} = CRM.update(c.scope, record, %{"name" => "Human correction", "city" => "Montréal"})
    {:ok, _} = CRM.link_contact(c.scope, contact)

    assert {:ok, %{person: %{name: "Human correction", city: "Montréal"}, sources: [source]}} =
             CRM.get_legacy(c.scope, contact.id)

    assert CRM.origins(c.scope, link.person_id) == [contact]
    assert source.original["city"] == "Québec"
    assert Repo.aggregate(PhoenixCRM.Source, :count) == 1
  end

  test "saved drafts cannot leak a recipient removed from the selection after group revocation",
       c do
    manager =
      user_fixture()
      |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
      |> Repo.update!()

    {:ok, _} = Volunteers.assign_manager(c.scope, c.member.organizing_group_id, manager.email)
    scope = Scope.for_user(manager)
    {:ok, batch} = Mail.create(scope, c.member.id)
    {:ok, batch} = Mail.save_batch(scope, batch, %{"subject" => "Hello", "source" => "Body"})
    {:ok, [draft]} = Mail.generate(scope, batch.id)

    Repo.get!(PauseAiCa.Accounts.User, c.member.id)
    |> Ecto.Changeset.change(organizing_group_id: nil)
    |> Repo.update!()

    assert {:error, :unauthorized} = Mail.get(scope, batch.id)
    assert {:error, :unauthorized} = Mail.save_draft(scope, draft, %{"source" => "Late"})
    assert Repo.get!(Mail.Draft, draft.id).source == "Body"
  end

  test "draft preparation bounds recipients and never grants newsletter consent", c do
    {:ok, batch} = Mail.create(c.scope, c.member.id)

    users =
      for _ <- 1..5,
          do:
            user_fixture()
            |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
            |> Repo.update!()

    flush_fixture_emails()

    assert {:error, %Ecto.Changeset{}} =
             Mail.save_batch(c.scope, batch, %{
               "recipient_ids" => [c.member.id | Enum.map(users, & &1.id)]
             })

    refute Repo.get!(PauseAiCa.Accounts.User, c.member.id).local_updates
    refute_receive {:email, _}
  end

  defp flush_fixture_emails do
    receive do
      {:email, _} -> flush_fixture_emails()
    after
      0 -> :ok
    end
  end

  test "preview renders Markdown while removing active markup and remote images" do
    html =
      Mail.Render.html(
        "# Draft\n<script>alert(1)</script>\n![tracker](https://example.org/pixel)\n[bad](javascript:alert(1))\n[good](https://pauseai.ca)"
      )

    assert html =~ "<h1>Draft</h1>"
    refute html =~ "<script"
    refute html =~ "<img"
    refute html =~ "href=\"javascript:"
    assert html =~ "href=\"https://pauseai.ca\""
  end
end
