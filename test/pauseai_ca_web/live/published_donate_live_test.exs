defmodule PauseAiCaWeb.PublishedDonateLiveTest do
  use PauseAiCaWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import PauseAiCa.AccountsFixtures
  alias PauseAiCa.Repo
  alias PauseAiCa.Accounts.Scope
  alias PauseAiCa.Donations.{Page, PageRevision, Pages, Pledge}
  alias PauseAiCaWeb.DonationPageContent

  test "public fallback reads do not create CMS records", %{conn: conn} do
    for path <- ["/en/donate", "/fr/faire-un-don"] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#donation-email", "pauseaicanada@proton.me")
      refute has_element?(view, "#donation-gift-form")
    end

    assert Repo.aggregate(Page, :count) == 0
    assert Repo.aggregate(PageRevision, :count) == 0
  end

  test "only the published bilingual snapshot reaches the public page", %{conn: conn} do
    scope = admin_scope()
    {:ok, page} = Pages.get_or_create(scope)
    payload = payload()
    {:ok, draft} = Pages.save(scope, page, payload)
    {:ok, before, _} = live(conn, "/en/donate")
    refute has_element?(before, "h1", "Published English title")
    {:ok, published} = Pages.publish(scope, draft)

    for {path, title} <- [
          {"/en/donate", "Published English title"},
          {"/fr/faire-un-don", "Titre français publié"}
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "h1", title)
      refute has_element?(view, "#donation-funding-unknown")
      refute has_element?(view, "#donation-gift-form")
      refute has_element?(view, "#donation-buckets")
      assert has_element?(view, "#manifund-donate[data-donation='manifund'][target='_blank']")
      assert has_element?(view, "#donation-brochure[data-donation='brochure']")
      assert has_element?(view, "#donation-email", "pauseaicanada@proton.me")
    end

    later = put_in(payload, ["editions", "en", "title"], "Secret unfinished draft")
    assert {:ok, _} = Pages.save(scope, published, later)
    {:ok, view, _} = live(conn, "/en/donate")
    assert has_element?(view, "h1", "Published English title")
    refute render(view) =~ "Secret unfinished draft"
  end

  test "Interac starts closed during the active campaign and open afterwards", %{conn: conn} do
    previous = Application.get_env(:pauseai_ca, :manifund_donations_enabled)
    on_exit(fn -> Application.put_env(:pauseai_ca, :manifund_donations_enabled, previous) end)
    publish(payload())

    for active <- [true, false] do
      Application.put_env(:pauseai_ca, :manifund_donations_enabled, active)
      {:ok, view, _} = live(conn, "/fr/faire-un-don")
      assert has_element?(view, "details#donate-interac > summary")
      assert has_element?(view, "details#donate-interac[open]") == not active
    end
  end

  test "gift preview retains newly completed goals, preserves ties and never saves a pledge", %{
    conn: conn
  } do
    enable_funding(0)
    publish(payload())
    revision_count = Repo.aggregate(PageRevision, :count)
    {:ok, view, _} = live(conn, "/en/donate")
    assert bucket_ids(render(view)) == ["bucket:first:small-first"]

    html = view |> form("#donation-gift-form", gift: %{amount: "50"}) |> render_change()
    assert bucket_ids(html) == ["bucket:first:small-first", "bucket:first:small-second"]
    refute has_element?(view, "#donation-funding-unknown")

    html = view |> form("#donation-gift-form", gift: %{amount: ""}) |> render_change()
    assert bucket_ids(html) == ["bucket:first:small-first"]
    html = view |> render_change("preview_gift", %{"gift" => %{"amount" => "bad"}})
    assert html =~ Pages.defaults()["editions"]["en"]["gift_invalid"]
    assert has_element?(view, "#donation-gift[value='bad']")
    render_click(view, "save", %{"pledge" => %{"amount" => "50"}})
    assert Repo.aggregate(Pledge, :count) == 0
    assert Repo.aggregate(PageRevision, :count) == revision_count
  end

  test "known observations select remaining mode, while CMS preview controls stay local and links inert" do
    page = payload()

    html =
      render_component(&DonationPageContent.content/1,
        page: page,
        locale: "en",
        observation: %{amount_minor: 15_001, currency: "CAD"},
        preview_mode: true,
        preview_event: "preview_gift_change",
        gift_minor: 2_500,
        gift_value: "25"
      )

    assert html =~ "Remaining authored heading"
    refute html =~ "id=\"donation-cms-preview-funding-unknown\""
    document = LazyHTML.from_fragment(html)

    assert LazyHTML.query(document, "#donation-cms-preview-gift-form")
           |> LazyHTML.attribute("phx-change") == ["preview_gift_change"]

    assert LazyHTML.query(document, "#donation-cms-preview-gift")
           |> LazyHTML.attribute("disabled") == []

    assert LazyHTML.query(document, "a") |> LazyHTML.attribute("href") == []
    assert LazyHTML.query(document, "[data-donation]") |> Enum.empty?()
    refute html =~ "TrackOutbound"

    at_threshold =
      render_component(&DonationPageContent.content/1,
        page: page,
        locale: "en",
        observation: %{amount_minor: 15_000, currency: "CAD"}
      )

    refute at_threshold =~ "Remaining authored heading"
  end

  test "blank optional allocation headings never leave an orphaned accessible-name reference" do
    page =
      payload()
      |> put_in(["editions", "en", "allocation_heading"], "")
      |> put_in(["editions", "en", "remaining_heading"], "")

    for observation <- [nil, %{amount_minor: 15_001, currency: "CAD"}] do
      html =
        render_component(&DonationPageContent.content/1,
          page: page,
          locale: "en",
          observation: observation,
          preview_mode: true
        )

      document = LazyHTML.from_fragment(html)
      assert LazyHTML.query(document, "section[aria-labelledby]") |> Enum.empty?()
      assert LazyHTML.query(document, "#donation-cms-preview-allocation-heading") |> Enum.empty?()
      refute LazyHTML.query(document, "#donation-cms-preview-buckets") |> Enum.empty?()
    end
  end

  test "mobile dialog shares one projected result with unique IDs and a compact input" do
    html =
      render_component(&DonationPageContent.content/1,
        page: payload(),
        locale: "en",
        observation: %{amount_minor: 0, currency: "CAD"},
        gift_minor: 5_000,
        gift_value: "50"
      )

    document = LazyHTML.from_fragment(html)
    ids = document |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
    assert Enum.uniq(ids) == ids

    assert LazyHTML.query(document, "#donation-mobile-open[aria-haspopup=dialog]")
           |> LazyHTML.text()
           |> String.trim() == "Try a donation"

    assert LazyHTML.query(document, "#donation-mobile-dialog[open]") |> Enum.empty?()

    assert LazyHTML.query(document, "#donation-mobile-dialog")
           |> LazyHTML.attribute("aria-labelledby") == ["donation-mobile-title"]

    assert LazyHTML.query(document, "#donation-mobile-gift[value='50']") |> Enum.count() == 1
    assert LazyHTML.query(document, "#donation-mobile-dialog [autofocus]") |> Enum.empty?()
    assert LazyHTML.query(document, "#donation-mobile-dialog a[href]") |> Enum.empty?()

    refute LazyHTML.query(document, "#donation-mobile-dialog") |> LazyHTML.text() =~
             payload()["editions"]["en"]["gift_note"]

    desktop =
      LazyHTML.query(document, "#donation-buckets")
      |> LazyHTML.attribute("data-cards")
      |> hd()
      |> Jason.decode!()

    mobile =
      LazyHTML.query(document, "#donation-mobile-buckets")
      |> LazyHTML.attribute("data-cards")
      |> hd()
      |> Jason.decode!()

    assert mobile == desktop
    assert Enum.any?(mobile, &(&1["key"] == "bucket:first:small-first" and &1["full"]))
    assert Enum.any?(mobile, &(&1["key"] == "bucket:first:small-second"))
  end

  test "mobile CMS preview uses its own form namespace and keeps links inert" do
    html =
      render_component(&DonationPageContent.content/1,
        page: payload(),
        locale: "en",
        preview_mode: true,
        preview_event: "preview-gift",
        gift_minor: 5_000,
        gift_value: "50"
      )

    document = LazyHTML.from_fragment(html)

    assert LazyHTML.query(document, "#donation-cms-preview-mobile-gift-form")
           |> LazyHTML.attribute("phx-change") == ["preview-gift"]

    assert LazyHTML.query(document, "#donation-cms-preview-mobile-gift[value='50']")
           |> Enum.count() == 1

    assert LazyHTML.query(document, "#donation-cms-preview-mobile-dialog a[href]")
           |> Enum.empty?()

    assert LazyHTML.query(document, "#donation-cms-preview-mobile-dialog [data-donation]")
           |> Enum.empty?()

    assert LazyHTML.query(
             document,
             "#donation-cms-preview-mobile-dialog [phx-hook*='TrackOutbound']"
           )
           |> Enum.empty?()
  end

  test "public funding uses only the configured campaign and discloses the dated pending-offer measure",
       %{conn: conn} do
    enable_funding(15_001)
    published = publish(payload())
    {:ok, view, html} = live(conn, "/en/donate")
    assert has_element?(view, "#donation-funding-source", "Pending Manifund offers")
    assert html =~ "These offers have not been received"
    assert html =~ "1.4038"
    assert has_element?(view, "#donation-gift-form")
    assert html =~ "Remaining authored heading"

    changed =
      put_in(payload(), ["links", "campaign"], "https://manifund.org/projects/another-project")

    scope = admin_scope()
    {:ok, draft} = Pages.save(scope, published, changed)
    {:ok, _} = Pages.publish(scope, draft)
    {:ok, mismatched, _} = live(conn, "/en/donate")
    refute has_element?(mismatched, "#donation-funding-source")
    refute has_element?(mismatched, "#donation-gift-form")
    assert has_element?(mismatched, "#manifund-donate")
  end

  defp enable_funding(amount) do
    keys = [:donation_funding_enabled, :manifund_donations_enabled, :donation_funding_cache]
    previous = Map.new(keys, &{&1, Application.fetch_env(:pauseai_ca, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:pauseai_ca, key, value)
          :error -> Application.delete_env(:pauseai_ca, key)
        end
      end
    end)

    {:ok, campaign} = PauseAiCa.Donations.Campaign.current()
    now = DateTime.utc_now()

    value = %{
      project_id: campaign.project_id,
      amount_minor: amount,
      currency: "CAD",
      measure: :pending_offers,
      received_minor: nil,
      fx_rate: "1.4038",
      fx_date: DateTime.to_date(now),
      fetched_at: now
    }

    parent = self()

    cache =
      start_supervised!(
        {PhoenixDonations.Cache,
         fetcher: fn ->
           send(parent, {:fetch_started, self()})

           receive do
             :release -> {:ok, value}
           end
         end,
         refresh_interval_ms: :infinity,
         max_age_seconds: 900}
      )

    assert_receive {:fetch_started, worker}
    ref = Process.monitor(worker)
    send(worker, :release)
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
    assert {:ok, _} = PauseAiCa.Donations.Funding.observation(cache, now)
    Application.put_env(:pauseai_ca, :donation_funding_enabled, true)
    Application.put_env(:pauseai_ca, :manifund_donations_enabled, true)
    Application.put_env(:pauseai_ca, :donation_funding_cache, cache)
  end

  defp admin_scope do
    user_fixture()
    |> Ecto.Changeset.change(superadmin: true)
    |> Repo.update!()
    |> Scope.for_user()
  end

  defp publish(payload) do
    scope = admin_scope()
    {:ok, page} = Pages.get_or_create(scope)
    {:ok, draft} = Pages.save(scope, page, payload)
    {:ok, published} = Pages.publish(scope, draft)
    published
  end

  defp bucket_ids(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#donation-buckets")
    |> LazyHTML.attribute("data-cards")
    |> hd()
    |> Jason.decode!()
    |> Enum.filter(&(&1["kind"] == "bucket"))
    |> Enum.map(& &1["key"])
  end

  defp payload do
    Pages.defaults()
    |> put_in(["editions", "en", "title"], "Published English title")
    |> put_in(["editions", "fr", "title"], "Titre français publié")
    |> put_in(["editions", "en", "remaining_heading"], "Remaining authored heading")
    |> Map.put("stages", [
      %{
        "id" => "first",
        "label_en" => "First complete budget",
        "label_fr" => "Premier budget complet",
        "target_minor" => 30_000,
        "buckets" => [
          bucket("large", 20_000),
          bucket("small-first", 5_000),
          bucket("small-second", 5_000)
        ]
      },
      %{
        "id" => "second",
        "label_en" => "Second complete budget",
        "label_fr" => "Deuxième budget complet",
        "target_minor" => 50_000,
        "buckets" => [bucket("next", 50_000)]
      }
    ])
  end

  defp bucket(id, amount),
    do: %{"id" => id, "label_en" => id, "label_fr" => id, "amount_minor" => amount}
end
