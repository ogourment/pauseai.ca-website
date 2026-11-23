if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.ChapterPagesTest do
    use AcceptanceHarness.Playwright.Case, async: false

    import PauseAiCa.AccountsFixtures

    alias PauseAiCa.{Accounts, Incubators, Repo, Volunteers}
    alias PauseAiCaWeb.AtddEvidence
    alias PhoenixTest.Playwright

    @moduletag :atdd
    @scenario %{
      id: "CHAPTER-PAGES-01",
      title: "A manager publishes a chapter page for readers",
      tags: ["chapters", "cms"],
      roles: ["Chapter manager", "Signed-out reader", "Administrator"],
      language: "English",
      device: "Desktop",
      source_file: "test/pauseai_ca_web/atdd/chapter_pages_atdd_test.exs"
    }

    setup_all do
      AtddEvidence.reset!(@scenario.title, [@scenario], %{
        browser: "Chromium",
        viewport: "Desktop"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    @tag browser_context_opts: [viewport: %{width: 1280, height: 900}]
    test "CHAPTER-PAGES-01 private drafts and public chapter pages", context do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      admin =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()
        |> Accounts.Scope.for_user()

      manager = user_fixture()
      {:ok, group} = Volunteers.create_group(admin, %{name: "Lakeside"})
      {:ok, grant} = Volunteers.assign_manager(admin, group.id, manager.email)

      {:ok, profile} =
        Incubators.configure(admin, group.id, %{
          "name_en" => "Lakeside",
          "name_fr" => "Lakeside",
          "area_served" => "local",
          "fsas" => "H2X",
          "published" => true
        })

      {:ok, draft} =
        Incubators.save_chapter(admin, group.id, profile.revision, %{
          "slug" => "lakeside-acceptance",
          "en" => "Welcome to Lakeside.",
          "fr" => ""
        })

      {:ok, _} = Incubators.publish_chapter(admin, group.id, draft.revision)

      chapter = "/groups/lakeside-acceptance"
      public_page = "#{chapter}/pages/meetups"
      editor_path = "/manage/groups/#{group.id}/pages/meetups"
      preview_path = "#{editor_path}/preview"
      title = "Lakeside meetups"
      body = "Meet **local volunteers**."
      new_title = "Lakeside volunteer schedule"
      new_body = "Bring a **new volunteer**."

      {token, _} = generate_user_magic_link_token(manager)

      editor =
        context.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/manage/groups/#{group.id}/homepage?locale=en")
        |> click_link("Manage chapter pages")
        |> assert_has("#chapter-pages-new", text: "Add page", exact: true)
        |> Playwright.click("#chapter-pages-new")
        |> assert_has("[data-phx-main].phx-connected")
        |> fill_in("Title", with: title)
        |> fill_in("Page address", with: "meetups")
        |> fill_in("Content", with: body)
        |> click_button("Save draft")
        |> assert_path(editor_path)
        |> assert_has("#flash-info", text: "Draft saved", exact: true)
        |> visit("#{editor_path}?locale=en")
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("input[name='content[title]']", value: title)
        |> assert_has("textarea[name='content[body]']", value: body)

      :ok = PlaywrightEx.subscribe(editor.context_id)

      preview =
        editor
        |> open_preview()
        |> assert_path(preview_path)
        |> assert_has("#private-chapter-preview h1", text: title, exact: true)
        |> assert_has("#private-chapter-preview strong", text: "local volunteers", exact: true)
        |> capture(1, "Preview private draft", "The saved draft renders in an authenticated tab.")

      {:ok, _} = PlaywrightEx.Page.close(preview.page_id, timeout: 5_000)

      reader_config =
        Playwright.Config.validate!(browser_context_opts: [viewport: %{width: 1280, height: 900}])

      reader =
        Playwright.Case.new_session(reader_config, context)
        |> visit("#{chapter}?locale=en")
        |> assert_has("h1", text: "Lakeside", exact: true)
        |> refute_has("#chapter-page-navigation a", text: title, exact: true)
        |> visit("#{public_page}?locale=en")
        |> assert_has("body", text: "Not Found", exact: true)
        |> visit("#{preview_path}?locale=en")
        |> assert_path("/users/log-in")
        |> refute_has("#private-chapter-preview")
        |> capture(2, "Open the preview address as a reader", "The reader is asked to sign in.")

      editor
      |> click_button("Publish saved draft")
      |> assert_has("#chapter-page-status", text: "Published", exact: true)

      reader =
        reader
        |> visit("#{chapter}?locale=en")
        |> click_link(title)
        |> assert_path(public_page)
        |> assert_has("#published-chapter-page h1", text: title, exact: true)
        |> assert_has("#published-chapter-page strong", text: "local volunteers", exact: true)
        |> capture(
          3,
          "Follow the chapter navigation link",
          "The published title and text are visible."
        )

      editor
      |> fill_in("Title", with: new_title)
      |> fill_in("Content", with: new_body)
      |> click_button("Save draft")
      |> assert_has("#chapter-page-status", text: "Draft saved", exact: true)

      preview =
        editor
        |> open_preview()
        |> assert_has("#private-chapter-preview h1", text: new_title, exact: true)
        |> assert_has("#private-chapter-preview strong", text: "new volunteer", exact: true)
        |> capture(4, "Preview the revised draft", "The revised draft is visible to the manager.")

      {:ok, _} = PlaywrightEx.Page.close(preview.page_id, timeout: 5_000)

      reader
      |> visit("#{public_page}?locale=en")
      |> assert_has("#published-chapter-page h1", text: title, exact: true)
      |> assert_has("#published-chapter-page strong", text: "local volunteers", exact: true)
      |> refute_has("#published-chapter-page", text: new_title)
      |> refute_has("#published-chapter-page", text: "new volunteer")

      :ok = Volunteers.revoke_manager(admin, grant.id)
      editor |> click_button("Publish saved draft") |> assert_path("/manage/groups")

      reader
      |> visit("#{public_page}?locale=en")
      |> assert_has("#published-chapter-page h1", text: title, exact: true)
      |> assert_has("#published-chapter-page strong", text: "local volunteers", exact: true)
      |> refute_has("#published-chapter-page", text: "new volunteer")
      |> capture(
        5,
        "Reload after the revoked manager tried to publish",
        "The last publication is still visible."
      )

      AtddEvidence.mark_scenario_success!(@scenario)
    end

    defp open_preview(editor) do
      click_link(editor, "Preview private draft")

      assert_receive {:playwright_msg, %{method: :page, params: %{page: %{guid: page_id}}}},
                     5_000

      %{main_frame: %{guid: frame_id}} =
        PlaywrightEx.Connection.initializer!(PlaywrightEx.Supervisor.Connection, page_id)

      %{editor | page_id: page_id, frame_id: frame_id}
    end

    defp capture(browser, step, control, outcome) do
      Playwright.evaluate(browser, "location.href", &Process.put(:chapter_evidence_url, &1))
      filename = "#{@scenario.id}-#{step}.png"

      metadata = %{
        "scenario_id" => @scenario.id,
        "step" => step,
        "url" => AtddEvidence.safe_url(Process.get(:chapter_evidence_url)),
        "control" => control,
        "source" => "Isolated application with synthetic chapter and accounts",
        "external_systems" => "No external publication or communication"
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
