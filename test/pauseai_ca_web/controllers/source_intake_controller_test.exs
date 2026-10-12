defmodule PauseAiCaWeb.SourceIntakeControllerTest do
  use PauseAiCaWeb.ConnCase
  alias PauseAiCa.{Repo, SourceIntake, ContactMigration, CRM}

  setup do
    old = Application.get_env(:pauseai_ca, :crm_intake_token)
    token = String.duplicate("synthetic-key-", 4)
    Application.put_env(:pauseai_ca, :crm_intake_token, token)
    on_exit(fn -> Application.put_env(:pauseai_ca, :crm_intake_token, old) end)
    %{token: token}
  end

  defp payload do
    %{
      "source" => "global-registration",
      "event_id" => "gmail/synthetic-01",
      "rows" => [
        %{
          "email" => "intake@example.org",
          "source_key" => "gmail/synthetic-01",
          "name" => "Original",
          "signup_date" => "2025-07-16",
          "weekly_hours" => "2–5",
          "email_subscription" => "No"
        }
      ]
    }
  end

  defp send_payload(conn, token, payload) do
    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> post("/api/crm/observations", payload)
  end

  test "denies unknown/disabled keys without writes", %{conn: conn} do
    assert conn |> send_payload("wrong", payload()) |> json_response(401)
    Application.put_env(:pauseai_ca, :crm_intake_token, nil)

    assert build_conn()
           |> send_payload(String.duplicate("synthetic-key-", 4), payload())
           |> json_response(401)

    assert Repo.aggregate(ContactMigration.Contact, :count) == 0
  end

  test "records service attribution and full sources, exact replay, conflict and zero outreach",
       %{conn: conn, token: token} do
    users = Repo.aggregate(PauseAiCa.Accounts.User, :count)
    first = conn |> send_payload(token, payload()) |> json_response(200)
    replay = build_conn() |> send_payload(token, payload()) |> json_response(200)
    assert replay["receipt_id"] == first["receipt_id"]
    assert replay["replayed"]
    [contact] = Repo.all(ContactMigration.Contact)
    assert contact.source_data["email_subscription"] == "No"
    [activity] = ContactMigration.list_activities(contact.id)
    assert activity.actor_user_id == nil
    assert activity.details["actor_service"] == "source-intake"
    [receipt] = Repo.all(ContactMigration.Import)
    assert receipt.imported_by_id == nil
    assert receipt.actor_service == "source-intake"
    [source] = Repo.all(PhoenixCRM.Source)
    assert source.original["weekly_hours"] == "2–5"
    assert Repo.aggregate(PhoenixCRM.Person, :count) == 1
    changed = put_in(payload(), ["rows", Access.at(0), "name"], "Changed")
    assert build_conn() |> send_payload(token, changed) |> json_response(409)
    assert Repo.aggregate(ContactMigration.Contact, :count) == 1
    assert Repo.aggregate(PauseAiCa.Accounts.User, :count) == users

    for schema <- [
          PauseAiCa.Newsletters.Subscription,
          PauseAiCa.Newsletters.Batch,
          PauseAiCa.Newsletters.Delivery
        ],
        do: assert(Repo.aggregate(schema, :count) == 0)

    refute_received {:email, _}

    for action <- [:read, :update, :merge, :undo, :contact],
        do:
          assert(
            SourceIntake.Policy.authorize(:source_intake, action, nil) == {:error, :unauthorized}
          )

    assert CRM.context().policy.authorize(:source_intake, :import, nil) == {:error, :unauthorized}
  end

  test "new observations preserve human edits, withdrawal and erasure tombstones", %{
    conn: conn,
    token: token
  } do
    conn |> send_payload(token, payload()) |> json_response(200)
    [contact] = Repo.all(ContactMigration.Contact)

    contact
    |> Ecto.Changeset.change(name: "Human", classification: "do_not_contact")
    |> Repo.update!()

    next =
      payload()
      |> Map.put("event_id", "gmail/synthetic-02")
      |> put_in(["rows", Access.at(0), "name"], "Later source")

    assert build_conn() |> send_payload(token, next) |> json_response(200)
    assert Repo.get!(ContactMigration.Contact, contact.id).name == "Human"
    assert Repo.get!(ContactMigration.Contact, contact.id).classification == "do_not_contact"
    SourceIntake.suppress("intake@example.org")
    Repo.get_by!(CRM.ContactLink, contact_id: contact.id) |> Repo.delete!()
    Repo.delete!(Repo.get!(ContactMigration.Contact, contact.id))
    next = Map.put(next, "event_id", "gmail/synthetic-03")
    result = build_conn() |> send_payload(token, next) |> json_response(200)
    assert result["suppressed_count"] == 1
    assert Repo.aggregate(ContactMigration.Contact, :count) == 0
  end

  test "Discord-only profiles keep immutable evidence without inventing addresses", %{
    conn: conn,
    token: token
  } do
    data = %{
      "source" => "discord",
      "event_id" => "discord/message-01",
      "rows" => [
        %{
          "email" => "",
          "source_key" => "discord/user-01",
          "discord_user_id" => "user-01",
          "bio" => "Introduction"
        }
      ]
    }

    for _ <- 1..2, do: assert(conn |> send_payload(token, data) |> json_response(200))
    assert Repo.aggregate(SourceIntake.PendingSource, :count) == 1
    assert Repo.aggregate(ContactMigration.Contact, :count) == 0
    assert Repo.aggregate(PhoenixCRM.Person, :count) == 0
  end

  test "an erased unresolved identity is suppressed by its stable key", %{
    conn: conn,
    token: token
  } do
    SourceIntake.suppress("discord/erased-user")

    data = %{
      "source" => "discord",
      "event_id" => "discord/erased-message",
      "rows" => [
        %{"email" => "", "source_key" => "discord/erased-user", "bio" => "Earlier source"}
      ]
    }

    result = conn |> send_payload(token, data) |> json_response(200)
    assert result["suppressed_count"] == 1
    assert Repo.aggregate(SourceIntake.PendingSource, :count) == 0
  end

  test "rejects malformed and oversized input, arbitrary source and privilege claims", %{
    conn: conn,
    token: token
  } do
    for data <- [
          Map.put(payload(), "source", "arbitrary"),
          Map.put(payload(), "rows", List.duplicate(hd(payload()["rows"]), 26)),
          put_in(payload(), ["rows", Access.at(0), "email"], "invalid"),
          put_in(payload(), ["rows", Access.at(0), "superadmin"], true)
        ] do
      assert conn |> send_payload(token, data) |> json_response(422)
    end

    assert Repo.aggregate(ContactMigration.Contact, :count) == 0
  end
end
