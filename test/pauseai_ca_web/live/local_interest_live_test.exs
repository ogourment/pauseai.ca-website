defmodule PauseAiCaWeb.LocalInterestLiveTest do
  use PauseAiCaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures

  alias PauseAiCa.{Accounts, Participation, Repo}
  alias PauseAiCa.Participation.Request

  test "confirmed queue describes the request and identifies the follow-up organizer", %{
    conn: conn
  } do
    admin = organizer("Synthetic organizer")
    owner = organizer("Assigned organizer")
    request = request(%{followup_owner_id: owner.id})
    pending = request(%{email: "pending@example.org", state: "pending"})
    withdrawn = request(%{email: "withdrawn@example.org", withdrawn_at: DateTime.utc_now()})

    {:ok, view, _} = live(log_in_user(conn, admin), "/admin/local-interest?locale=en")
    row = "#local-request-#{request.id}"
    assert has_element?(view, "main .management-content > h1", "Local participation")
    assert has_element?(view, row, "Requested to join a local group")
    assert has_element?(view, row, "Follow-up by Assigned organizer")
    assert has_element?(view, "#{row} button", "I’ll follow up")
    refute has_element?(view, "#{row} button", "Take ownership")
    refute has_element?(view, "#local-request-#{pending.id}")
    refute has_element?(view, "#local-request-#{withdrawn.id}")

    view |> element("#{row} button", "I’ll follow up") |> render_click()
    assert Repo.reload!(request).followup_owner_id == admin.id
    assert has_element?(view, row, "Follow-up by Synthetic organizer")
    assert has_element?(view, row, "Your follow-up")
    refute has_element?(view, "#{row} button[phx-click=claim]")

    {:ok, reloaded, _} = live(log_in_user(conn, admin), "/admin/local-interest?locale=en")
    assert has_element?(reloaded, row, "Follow-up by Synthetic organizer")
  end

  test "organizer email is visible when the assigned account has no name", %{conn: conn} do
    admin = organizer(nil)
    request = request(%{followup_owner_id: admin.id, local_kind: "help"})
    {:ok, view, _} = live(log_in_user(conn, admin), "/admin/local-interest?locale=en")
    assert has_element?(view, "#local-request-#{request.id}", "Follow-up by #{admin.email}")
    assert has_element?(view, "#local-request-#{request.id}", "I can help")
  end

  test "ordinary accounts cannot open or claim the private queue", %{conn: conn} do
    user = user_fixture()
    request = request()
    scope = Accounts.Scope.for_user(user)
    assert {:error, :unauthorized} = Participation.local_requests(scope)
    assert {:error, :unauthorized} = Participation.claim(scope, request.id)
    assert conn |> log_in_user(user) |> get("/admin/local-interest?locale=en") |> response(403)
    assert is_nil(Repo.reload!(request).followup_owner_id)
  end

  defp organizer(name) do
    user_fixture()
    |> Ecto.Changeset.change(superadmin: true, name: name)
    |> Repo.update!()
  end

  defp request(extra \\ %{}) do
    now = DateTime.utc_now()

    Repo.insert!(
      struct!(
        Request,
        Map.merge(
          %{
            email: "local@example.org",
            locale: "en",
            state: "confirmed",
            local_kind: "waitlist",
            city: "Toronto",
            confirmed_at: now,
            expires_at: DateTime.add(now, 86_400),
            withdrawal_hash: :crypto.strong_rand_bytes(32)
          },
          extra
        )
      )
    )
  end
end
