defmodule PauseAiCaWeb.NewsletterRecipientExportControllerTest do
  use PauseAiCaWeb.ConnCase, async: true
  import Ecto.Changeset
  import Ecto.Query
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Repo}
  alias PauseAiCa.Newsletters.{Batch, Batches, Delivery, Drafts, RecipientExport}

  setup do
    actor = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(actor)
    {:ok, draft} = Drafts.create(scope)

    {:ok, draft} =
      Drafts.save(scope, draft, %{
        "subject" => "Reviewed subset",
        "source" => "A reviewed message."
      })

    addresses =
      for email <- ["selected-a@example.org", "selected-b@example.org", "outside@example.org"] do
        person = Repo.insert!(%PhoenixCRM.Person{name: "Synthetic contact"})
        Repo.insert!(%PhoenixCRM.Address{person_id: person.id, email: email})
      end

    {:ok, batch} =
      Batches.prepare(
        scope,
        draft,
        "contacts",
        Enum.map(Enum.take(addresses, 2), & &1.person_id),
        true
      )

    flush_emails()
    %{actor: actor, scope: scope, batch: batch, addresses: addresses}
  end

  test "downloads only the prepared snapshot without approval, delivery or directory expansion",
       c do
    [first | _] = c.addresses
    first |> change(email: "changed-after-preparation@example.org") |> Repo.update!()
    before_batch = Repo.get!(Batch, c.batch.id)
    before_deliveries = deliveries(c.batch.id)
    conn = c.conn |> log_in_user(c.actor) |> get(path(c.batch))

    assert response(conn, 200) ==
             "\"email\"\r\n\"selected-a@example.org\"\r\n\"selected-b@example.org\"\r\n"

    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

    assert get_resp_header(conn, "content-disposition") |> hd() =~
             "batch-#{c.batch.id}-recipients.csv"

    assert Repo.get!(Batch, c.batch.id) == before_batch
    assert deliveries(c.batch.id) == before_deliveries
    assert before_batch.state == "review" and is_nil(before_batch.approved_at)
    assert Enum.all?(before_deliveries, &(&1.state == "pending" and is_nil(&1.attempted_at)))
    refute_receive {:email, _}
  end

  test "anonymous and nonadmin users cannot download", c do
    assert c.conn |> get(path(c.batch)) |> redirected_to() == "/users/log-in"
    user = user_fixture()
    conn = c.conn |> log_in_user(user) |> get(path(c.batch))
    assert response(conn, 403) == "superadmin required"

    assert RecipientExport.download(Accounts.Scope.for_user(user), c.batch.id) ==
             {:error, :unauthorized}

    assert RecipientExport.download(nil, c.batch.id) == {:error, :unauthorized}
  end

  test "another administrator cannot export someone else's batch", c do
    other = user_fixture() |> change(superadmin: true) |> Repo.update!()
    conn = c.conn |> log_in_user(other) |> get(path(c.batch))
    assert response(conn, 404) == "Not found"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "fresh role and account confirmation are required despite a stale admin scope", c do
    c.actor |> change(superadmin: false) |> Repo.update!()
    assert RecipientExport.download(c.scope, c.batch.id) == {:error, :unauthorized}
    c.actor |> change(superadmin: true, confirmed_at: nil) |> Repo.update!()
    assert RecipientExport.download(c.scope, c.batch.id) == {:error, :unauthorized}
  end

  test "invalid and nonexistent batch IDs reveal no data", c do
    for id <- ["not-a-uuid", Ecto.UUID.generate()] do
      conn = c.conn |> log_in_user(c.actor) |> get("/manage/mail/batches/#{id}/recipients.csv")
      assert response(conn, 404) == "Not found"
    end
  end

  defp path(batch), do: "/manage/mail/batches/#{batch.id}/recipients.csv"

  defp deliveries(id),
    do: Repo.all(from(d in Delivery, where: d.batch_id == ^id, order_by: d.id))

  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end
end
