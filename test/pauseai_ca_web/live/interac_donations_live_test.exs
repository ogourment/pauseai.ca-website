defmodule PauseAiCaWeb.InteracDonationsLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Repo
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Donations.{Interac, InteracDeclaration, Pages}

  defp publish do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    scope = Scope.for_user(admin)
    {:ok, page} = Pages.get_or_create(scope)
    {:ok, _} = Pages.publish(scope, page)
    admin
  end

  test "public declaration stays inside Interac, retains invalid input, defaults anonymous and records only pending",
       %{conn: conn} do
    publish()
    {:ok, view, _} = live(conn, "/en/donate")
    assert has_element?(view, "#donate-interac:not([open]) #interac-declaration-form")
    assert has_element?(view, "#interac-declaration-anonymous option[selected][value=true]")
    assert has_element?(view, "#interac-declaration-name[required]")

    html =
      render_submit(view, "declare_interac", %{
        "interac" => %{
          "name" => "",
          "email" => "not-an-address",
          "amount" => "0",
          "_unused_name" => "",
          "submission_token" => nonce(view)
        }
      })

    assert html =~ "can&#39;t be blank" or html =~ "can&#x27;t be blank"
    assert has_element?(view, "#interac-declaration-email[value='not-an-address']")
    assert Repo.aggregate(InteracDeclaration, :count) == 0

    view
    |> form("#interac-declaration-form",
      interac: %{
        name: "Synthetic transfer sender",
        email: "sender@example.org",
        amount: "30.25",
        anonymous: "false"
      }
    )
    |> render_submit()

    assert has_element?(view, "#interac-declaration-status", "Awaiting bank verification")
    refute has_element?(view, "#interac-declaration-form")
    record = Repo.one!(InteracDeclaration)
    assert record.state == "pending"
    assert record.amount_minor == 3025
    refute record.anonymous
    assert record.account_ref == nil

    render_submit(view, "declare_interac", %{
      "interac" => %{"name" => "Duplicate", "email" => "sender@example.org", "amount" => "30.25"}
    })

    assert Repo.aggregate(InteracDeclaration, :count) == 1
  end

  test "signed-in account email is visibly read-only and forged values cannot link another account",
       %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)
    publish()
    {:ok, view, _} = live(conn, "/en/donate")
    assert has_element?(view, "#interac-declaration-email[readonly]")
    assert has_element?(view, "#interac-declaration", "Your account email is read-only here.")

    render_submit(view, "declare_interac", %{
      "interac" => %{
        "name" => "Transfer name",
        "email" => "forged@example.org",
        "amount" => "12.34",
        "account_ref" => Ecto.UUID.generate(),
        "submission_token" => nonce(view)
      }
    })

    record = Repo.one!(InteracDeclaration)
    assert record.account_ref == user.id
    assert record.email == user.email
    assert record.name == "Transfer name"
  end

  test "superadmin must explicitly check the bank receipt; ordinary accounts cannot see declarations",
       %{conn: conn} do
    admin = publish()

    {:ok, pending} =
      Interac.submit(
        nil,
        %{"name" => "Private sender", "email" => "private@example.org", "amount" => "20"},
        Ecto.UUID.generate()
      )

    admin_conn = log_in_user(conn, admin)
    {:ok, view, _} = live(admin_conn, "/admin/interac-donations/#{pending.id}")
    assert has_element?(view, "#interac-pending-count", "1")

    form_values = %{
      received_amount: "20",
      received_on: Date.to_iso8601(Date.utc_today()),
      bank_reference: "",
      verification_note: "Synthetic statement reviewed",
      confirmed_received: "false"
    }

    view |> form("#interac-verification-form", verification: form_values) |> render_submit()
    assert has_element?(view, "#flash-error", "Confirm that you checked")
    assert Repo.get!(InteracDeclaration, pending.id).state == "pending"

    view
    |> form("#interac-verification-form",
      verification: Map.put(form_values, :confirmed_received, "true")
    )
    |> render_submit()

    assert has_element?(view, "#interac-verified-receipt", "Bank receipt verified")
    assert has_element?(view, "#interac-verified-receipt", "No bank reference was recorded")
    assert has_element?(view, "#interac-received-total", "C$20")
    assert Repo.get!(InteracDeclaration, pending.id).verified_actor_id == admin.id
    ordinary = user_fixture()
    ordinary_conn = log_in_user(build_conn(), ordinary)
    denied = get(ordinary_conn, "/admin/interac-donations")
    assert denied.status == 403
    assert denied.resp_body == "superadmin required"
    assert {:error, :unauthorized} = Interac.get(Scope.for_user(ordinary), pending.id)
  end

  test "signed form nonce survives a new LiveView mount and exact replay records no duplicate", %{
    conn: conn
  } do
    publish()
    {:ok, first_view, _} = live(conn, "/en/donate")
    token = nonce(first_view)

    attrs = %{
      "name" => "Synthetic sender",
      "email" => "replay@example.org",
      "amount" => "15",
      "submission_token" => token
    }

    render_submit(first_view, "declare_interac", %{"interac" => attrs})
    {:ok, reconnected, _} = live(conn, "/en/donate")
    render_change(reconnected, "validate_interac", %{"interac" => attrs})
    assert nonce(reconnected) == token
    render_submit(reconnected, "declare_interac", %{"interac" => attrs})
    assert Repo.aggregate(InteracDeclaration, :count) == 1
    assert has_element?(reconnected, "#interac-declaration-status")
    {:ok, tampered, _} = live(conn, "/en/donate")

    render_submit(tampered, "declare_interac", %{
      "interac" => Map.put(attrs, "submission_token", "forged")
    })

    assert Repo.aggregate(InteracDeclaration, :count) == 1
    assert has_element?(tampered, "#flash-error")
  end

  defp nonce(view) do
    render(view)
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("input[name='interac[submission_token]']")
    |> LazyHTML.attribute("value")
    |> hd()
  end

  test "CMS preview uses the same compact form with every input disabled and no submission events" do
    html =
      render_component(&PauseAiCaWeb.DonationPageContent.content/1,
        page: Pages.defaults(),
        locale: "en",
        preview_mode: true
      )

    document = LazyHTML.from_fragment(html)
    refute LazyHTML.query(document, "#interac-preview-form") |> Enum.empty?()
    assert LazyHTML.query(document, "#interac-preview-form [phx-submit]") |> Enum.empty?()

    assert LazyHTML.query(
             document,
             "#interac-preview-form input:not([disabled]):not([type=hidden]), #interac-preview-form select:not([disabled]), #interac-preview-form button:not([disabled])"
           )
           |> Enum.empty?()
  end
end
