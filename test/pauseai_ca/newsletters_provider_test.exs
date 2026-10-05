defmodule PauseAiCa.NewslettersProviderTest do
  use PauseAiCa.DataCase, async: false
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Accounts, Newsletters}
  alias PauseAiCa.Newsletters.Provider

  setup do
    previous = Application.get_env(:pauseai_ca, :brevo_req_options)
    on_exit(fn -> Application.put_env(:pauseai_ca, :brevo_req_options, previous) end)
    :ok
  end

  test "refresh is read-only at Brevo, attributes provider blocks, preserves consent on failure and checks revoked roles" do
    author = user_fixture() |> change(superadmin: true) |> Repo.update!()
    scope = Accounts.Scope.for_user(author)
    {:ok, request} = Newsletters.request_signup("observed@example.org", %{consent: true})
    {:ok, confirmed} = Newsletters.confirm(request.confirmation_token)

    Application.put_env(:pauseai_ca, :brevo_req_options,
      plug: fn conn ->
        assert conn.method == "GET"
        assert conn.request_path =~ "observed"

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => 8, "emailBlacklisted" => true}))
      end
    )

    assert {:ok, _} = Provider.refresh(scope, confirmed.id)
    refute Newsletters.eligible?(confirmed.email)

    assert Repo.get!(Newsletters.Subscription, confirmed.id).confirmed_at ==
             confirmed.confirmed_at

    Application.put_env(:pauseai_ca, :brevo_req_options,
      plug: fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end
    )

    assert {:error, :unavailable} = Provider.refresh(scope, confirmed.id)
    assert {:ok, history} = Newsletters.history(scope, confirmed.id)
    assert length(history) == 3
    assert List.last(history).actor_id == author.id
    author |> change(superadmin: false) |> Repo.update!()
    assert {:error, :unauthorized} = Provider.refresh(scope, confirmed.id)
  end
end
