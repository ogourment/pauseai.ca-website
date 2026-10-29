if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.BlogTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Blog, Repo}
    alias PauseAiCaWeb.{AtddEvidence, BlogLive}
    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "BLOG-01-#{locale}",
                    title: "Reader chooses article depth · #{language}",
                    tags: ["blog", "cms"],
                    roles: ["Superadmin / reader"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)
    setup_all do
      AtddEvidence.reset!("BLOG-01 · editorial publication and reader attention", @scenarios, %{
        browser: "Chromium",
        viewport: "English desktop and French phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "BLOG-01 author and reader #{locale}", context do
        locale = unquote(locale)
        id = "BLOG-01-#{locale}"
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        scope = Accounts.Scope.for_user(admin)
        email = admin.email
        assert_receive {:email, %{to: [{_, ^email}]}}, 1_000
        {:ok, article} = Blog.create(scope, "attention-choice")

        payload = %{
          "en" => %{
            "title" => "Synthetic article",
            "summary" => "The short summary is always visible.",
            "details" => "## Key details\n\nA little more context.",
            "full" => "## Complete source\n\nThe complete synthetic explanation."
          },
          "fr" => %{
            "title" => "Article fictif",
            "summary" => "Le résumé court est toujours visible.",
            "details" => "## Points clés\n\nUn peu plus de contexte.",
            "full" => "## Source complète\n\nL’explication fictive au complet."
          }
        }

        {:ok, article} = Blog.save(scope, article, payload)
        baseline = counts()
        {token, _} = generate_user_magic_link_token(admin)

        title =
          if locale == "fr", do: "Choisir le niveau de détail", else: "Choose how much to read"

        path = BlogLive.path(locale) <> "/" <> article.slug

        browser =
          context.conn
          |> visit("/users/log-in/#{token}")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/manage/blog/#{article.id}?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")
          |> capture(
            id,
            "Open saved draft",
            "The editor shows bilingual article fields before publication"
          )
          |> fill_in("#blog-#{locale}-title", tr(locale, "Title"), with: title)
          |> assert_has("#blog-save-status", text: tr(locale, "Unsaved changes"))
          |> click_button(tr(locale, "Save"))
          |> assert_has("#blog-save-status", text: tr(locale, "Saved"))
          |> capture(id, "Save", "Saved draft remains separate from the public blog")

        assert Blog.published(article.slug) == nil

        browser =
          browser
          |> PhoenixTest.Playwright.click("button[name='intent'][value='preview']")
          |> assert_has("#blog-preview", text: title)
          |> capture(id, "Preview", "Both language editions use the actual article renderer")
          |> click_button(tr(locale, "Publish"))
          |> visit(path)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("h1", text: title)
          |> assert_has("#blog-summary", text: payload[locale]["summary"])
          |> refute_has("#blog-details[open]")
          |> capture(
            id,
            "Publish then open article",
            "Reader sees title and short summary; optional sections are collapsed"
          )
          |> click_link(
            "nav[aria-label='#{tr(locale, "Reading depth")}'] a",
            tr(locale, "More details")
          )
          |> assert_has("#blog-details[open]")
          |> refute_has("#blog-full[open]")
          |> capture(
            id,
            "More details",
            "Reader opens key detail while the full text remains collapsed"
          )
          |> click_link(
            "nav[aria-label='#{tr(locale, "Reading depth")}'] a",
            tr(locale, "Everything")
          )
          |> assert_has("#blog-full[open]")
          |> capture(
            id,
            "Everything",
            "Reader can select the full text and share its stable depth URL"
          )
          |> visit(path <> "?depth=full")
          |> assert_has("#blog-full[open]")
          |> click_link(
            "nav[aria-label='#{tr(locale, "Reading depth")}'] a",
            tr(locale, "In brief")
          )
          |> refute_has("#blog-details[open]")

        assert counts() == baseline
        refute_receive {:email, _}
        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
        browser
      end
    end

    defp counts do
      Map.new(
        [
          Accounts.User,
          PauseAiCa.Newsletters.Subscription,
          PauseAiCa.Newsletters.Batch,
          PauseAiCa.Newsletters.Delivery
        ],
        &{&1, Repo.aggregate(&1, :count)}
      )
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, id, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        browser,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      PhoenixTest.Playwright.evaluate(browser, "location.href", &Process.put(:blog_url, &1))
      step = Process.get({:blog_step, id}, 0) + 1
      Process.put({:blog_step, id}, step)
      filename = "#{id}-#{step}.png"

      metadata = %{
        "scenario_id" => id,
        "step" => step,
        "url" => AtddEvidence.safe_url(Process.get(:blog_url)),
        "control" => control,
        "source" => "Actual isolated CMS and public runtime; synthetic article and account",
        "external_systems" =>
          "No external content publication, account creation, newsletter subscription or email"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, control, outcome, metadata)
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        control,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
