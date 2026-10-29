defmodule PauseAiCaWeb.DonationPageLiveTest do
  use PauseAiCaWeb.ConnCase
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.{Repo, Donations.Pages}
  alias PauseAiCa.Accounts.Scope

  setup %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
    %{admin: admin, scope: Scope.for_user(admin), conn: log_in_user(conn, admin)}
  end

  test "countdown settings stay draft-only until saved and published", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, "/manage/donations?locale=en")
    assert has_element?(view, "#donation-countdown-deadline")

    deadline =
      DateTime.utc_now()
      |> DateTime.add(30 * 86_400)
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()

    values = %{
      "page" => %{
        "campaign" => %{
          "enabled" => "true",
          "closes_at" => deadline,
          "urgent_window_days" => "3"
        }
      }
    }

    view |> form("#donation-page-form", values) |> render_submit(%{"intent" => "save"})
    {:ok, page} = Pages.get_or_create(scope)
    assert page.payload["campaign"]["urgent_window_days"] == 3
    assert page.payload["campaign"]["closes_at"] == deadline
    assert Pages.published() == nil
    assert {:ok, _} = Pages.publish(scope, page)
    {:ok, public, _} = live(build_conn(), "/en/donate")
    assert has_element?(public, "#donation-countdown[data-closes-at='#{deadline}']")
    assert render(public) =~ "Campaign closes #{String.slice(deadline, 0, 10)}."
    refute has_element?(public, "#montreal-protest-banner")
  end

  test "draft edits, preview, publish and restoration remain separate", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, "/manage/donations?locale=en")
    {:ok, original} = Pages.get_or_create(scope)
    assert has_element?(view, "[data-navigation-item='pauseai.donations'][aria-current='page']")

    values = %{"page" => %{"editions" => %{"en" => %{"title" => "A saved donation draft"}}}}
    view |> form("#donation-page-form", values) |> render_change()
    assert has_element?(view, "#donation-save-status", "Unsaved changes")
    assert has_element?(view, "#donation-publish[disabled]")
    view |> form("#donation-page-form", values) |> render_submit(%{"intent" => "preview"})
    assert has_element?(view, "#donation-preview", "A saved donation draft")
    {:ok, unchanged} = Pages.get_or_create(scope)
    assert unchanged.revision == original.revision
    assert Pages.published() == nil

    view |> form("#donation-page-form", values) |> render_submit(%{"intent" => "save"})
    assert has_element?(view, "#donation-save-status", "Saved")
    assert Pages.published() == nil
    view |> form("#donation-page-form") |> render_submit(%{"intent" => "publish"})
    assert Pages.published()["editions"]["en"]["title"] == "A saved donation draft"
    {:ok, public_page} = Pages.get_or_create(scope)

    {:ok, history} = Pages.history(scope)
    original_revision = Enum.find(history, &(&1.revision == original.revision))

    view
    |> element("button[phx-click=restore][phx-value-id='#{original_revision.id}']")
    |> render_click()

    {:ok, restored} = Pages.get_or_create(scope)
    assert restored.revision > public_page.revision
    assert restored.published_payload == public_page.published_payload
    assert restored.payload == original.payload
  end

  test "Publish receives the newest fields and requires a saved draft", %{conn: conn} do
    {:ok, view, _} = live(conn, "/manage/donations?locale=en")

    view
    |> form("#donation-page-form", %{
      "page" => %{"editions" => %{"en" => %{"title" => "Typed just before Publish"}}}
    })
    |> render_submit(%{"intent" => "publish"})

    assert has_element?(view, "#donation-editor-error", "Save your changes before publishing.")
    assert has_element?(view, "#donation-en-title", "Typed just before Publish")
    assert Pages.published() == nil
  end

  test "invalid link errors use readable field labels and retain input", %{conn: conn} do
    {:ok, view, _} = live(conn, "/manage/donations?locale=en")

    view
    |> form("#donation-page-form", %{
      "page" => %{"links" => %{"campaign" => "https://unknown.example.org/project"}}
    })
    |> render_submit()

    assert has_element?(view, "#donation-editor-error", "Campaign URL")

    assert has_element?(
             view,
             "#donation-campaign-url[value='https://unknown.example.org/project']"
           )

    refute render(view) =~ "links.campaign"
  end

  test "stage and bucket CAD edits preserve exact cents and stable IDs", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, "/manage/donations?locale=en")
    {:ok, page} = Pages.get_or_create(scope)
    [stage | _] = page.payload["stages"]
    [bucket | _] = stage["buckets"]
    cad = fn value -> value |> Decimal.new() |> Decimal.div(100) |> Decimal.to_string(:normal) end

    values = %{
      "page" => %{
        "stages" => %{
          "0" => %{
            "target_cad" => cad.(stage["target_minor"] + 1),
            "buckets" => %{"0" => %{"amount_cad" => cad.(bucket["amount_minor"] + 1)}}
          }
        }
      }
    }

    view |> form("#donation-page-form", values) |> render_submit()
    {:ok, saved} = Pages.get_or_create(scope)
    [changed | _] = saved.payload["stages"]
    assert changed["id"] == stage["id"]
    assert changed["target_minor"] == stage["target_minor"] + 1
    assert hd(changed["buckets"])["amount_minor"] == bucket["amount_minor"] + 1
    assert Enum.map(changed["buckets"], & &1["id"]) == Enum.map(stage["buckets"], & &1["id"])
    assert Pages.published() == nil
  end

  test "interactive preview simulations never persist funding or gift values", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _} = live(conn, "/manage/donations?locale=en")
    {:ok, original} = Pages.get_or_create(scope)
    view |> form("#donation-page-form") |> render_submit(%{"intent" => "preview"})

    view
    |> form("#donation-preview-funding-form", %{"funding" => %{"amount" => "900000"}})
    |> render_change()

    view
    |> form("#donation-cms-preview-gift-form", %{"gift" => %{"amount" => "25.01"}})
    |> render_change()

    assert has_element?(view, "#donation-preview-funding[value='900000']")
    assert has_element?(view, "#donation-cms-preview-gift[value='25.01']")
    assert has_element?(view, "#donation-preview", "synthetic")
    refute has_element?(view, "#donation-preview a[href]")
    {:ok, unchanged} = Pages.get_or_create(scope)
    assert unchanged.payload == original.payload
    assert unchanged.revision == original.revision
    assert Pages.published() == nil
  end

  test "browser untouched-field metadata never becomes CMS content", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, "/manage/donations?locale=en")

    values = %{
      "page" => %{
        "editions" => %{"en" => %{"title" => "Browser annotated draft", "_unused_lead" => ""}},
        "display" => %{"_unused_remaining_threshold_percent" => ""}
      }
    }

    view |> form("#donation-page-form") |> render_submit(values)
    refute has_element?(view, "#donation-editor-error")
    {:ok, page} = Pages.get_or_create(scope)
    assert page.payload["editions"]["en"]["title"] == "Browser annotated draft"
    refute Map.has_key?(page.payload["editions"]["en"], "_unused_lead")
    refute Map.has_key?(page.payload["display"], "_unused_remaining_threshold_percent")
    view |> form("#donation-page-form") |> render_submit(Map.put(values, "intent", "preview"))
    assert has_element?(view, "#donation-preview", "Browser annotated draft")
  end

  test "a stale editor retains actual fields until explicit reload", %{conn: conn, scope: scope} do
    {:ok, first, _} = live(conn, "/manage/donations?locale=en")
    {:ok, second, _} = live(conn, "/manage/donations?locale=en")

    first
    |> form("#donation-page-form", %{
      "page" => %{"editions" => %{"en" => %{"title" => "First saved version"}}}
    })
    |> render_submit()

    second
    |> form("#donation-page-form", %{
      "page" => %{"editions" => %{"en" => %{"title" => "My retained version"}}}
    })
    |> render_submit()

    assert has_element?(second, "#donation-conflict")
    assert has_element?(second, "#donation-en-title", "My retained version")
    {:ok, page} = Pages.get_or_create(scope)
    assert page.payload["editions"]["en"]["title"] == "First saved version"
    second |> element("button[phx-click=reload]") |> render_click()
    assert has_element?(second, "#donation-en-title", "First saved version")
    refute has_element?(second, "#donation-conflict")
  end

  test "revoked authority blocks editing and preview in an already open editor", %{
    conn: conn,
    admin: admin,
    scope: scope
  } do
    {:ok, view, _} = live(conn, "/manage/donations?locale=en")
    {:ok, page} = Pages.get_or_create(scope)
    admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

    result =
      view
      |> form("#donation-page-form", %{
        "page" => %{"editions" => %{"en" => %{"title" => "Revoked edit"}}}
      })
      |> render_submit(%{"intent" => "preview"})

    assert {:error, {:redirect, %{to: "/dashboard"}}} = result
    assert Repo.get!(PauseAiCa.Donations.Page, page.id).revision == page.revision
  end

  test "ordinary accounts cannot mount or see the donation editor", %{conn: _conn} do
    user = user_fixture()
    assert Pages.get_or_create(Scope.for_user(user)) == {:error, :unauthorized}

    assert {:error, {:redirect, %{to: "/dashboard"}}} =
             live(log_in_user(build_conn(), user), "/manage/donations")

    refute Enum.any?(
             PauseAiCaWeb.Navigation.assemble(Scope.for_user(user), "en"),
             &(&1.id == "pauseai.donations")
           )
  end

  test "stage and bucket order changes stay draft-only", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, "/manage/donations?locale=en")
    {:ok, page} = Pages.get_or_create(scope)
    [stage | _] = page.payload["stages"]
    [bucket | _] = stage["buckets"]

    view
    |> form("#donation-page-form")
    |> render_submit(%{"intent" => "bucket-add:#{stage["id"]}"})

    assert has_element?(view, "#donation-save-status", "Unsaved changes")

    assert length(Repo.get!(PauseAiCa.Donations.Page, page.id).payload["stages"]) ==
             length(page.payload["stages"])

    view
    |> form("#donation-page-form")
    |> render_submit(%{"intent" => "bucket-down:#{stage["id"]}:#{bucket["id"]}"})

    assert Pages.published() == nil
  end
end
