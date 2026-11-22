if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.ChapterPublishTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Incubators, Repo, Volunteers}
    @moduletag :atdd

    @tag browser_context_opts: [viewport: %{width: 1200, height: 850}]
    test "CHAPTER-PUBLISH-01 manager previews, publishes and loses publishing access", c do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      admin =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()
        |> Accounts.Scope.for_user()

      manager = user_fixture()
      {:ok, group} = Volunteers.create_group(admin, %{name: "Toronto"})
      {:ok, grant} = Volunteers.assign_manager(admin, group.id, manager.email)

      {:ok, _} =
        Incubators.configure(admin, group.id, %{
          "name_en" => "Toronto",
          "name_fr" => "Toronto",
          "published" => true
        })

      :ok = PlaywrightEx.subscribe(c.conn.context_id)

      editor =
        c.conn
        |> login(manager)
        |> visit("/manage/groups?group=#{group.id}")
        |> click_link("Edit chapter homepage")
        |> assert_has("[data-phx-main].phx-connected")
        |> fill_in("Chapter address under /groups/", with: "toronto")
        |> fill_in("English welcome",
          with: "## Toronto meetups\n\nMeet **local volunteers** in Toronto."
        )
        |> PhoenixTest.Playwright.click("#chapter-edition-en details summary")
        |> PhoenixTest.Playwright.click("#chapter-edition-en button[data-snippet]:first-of-type")
        |> click_button("Save draft")
        |> assert_has("#flash-info", text: "Draft saved")
        |> assert_has("#chapter-editor-en [data-pme-preview]", text: "Preview ↗", exact: true)
        |> PhoenixTest.Playwright.click("#chapter-editor-en [data-pme-preview]")
        |> assert_has("#chapter-editor-en [role=status]", text: "Preview updated")
        |> PhoenixTest.Playwright.evaluate(
          "window.open('', 'pme-chapter-editor-en').document.querySelector('iframe').srcdoc",
          fn html ->
            assert html =~ "<h2>Toronto meetups</h2>" and
                     html =~ "<strong>local volunteers</strong>"

            assert html =~ "toronto-crossing.jpg"
            refute html =~ "chapter-publish"
          end
        )
        |> refute_has("#chapter-preview")
        |> PhoenixTest.Playwright.evaluate("window.scrollTo(0,0)")
        |> PhoenixTest.Playwright.screenshot("chapter-manager-preview.png")

      assert_receive {:playwright_msg, %{method: :page, params: %{page: %{guid: popup}}}}, 5000
      {:ok, screenshot} = PlaywrightEx.Page.screenshot(popup, timeout: 5000)
      File.write!("tmp/atdd/screenshots/chapter-external-preview.png", Base.decode64!(screenshot))
      assert_raise Ecto.NoResultsError, fn -> Incubators.published_chapter!("toronto") end

      editor =
        editor
        |> click_button("Publish saved draft")
        |> assert_has("#flash-info", text: "Published")

      editor =
        editor
        |> fill_in("English welcome", with: "Private changes")
        |> click_button("Save draft")
        |> assert_has("#flash-info", text: "Draft saved")

      :ok = Volunteers.revoke_manager(admin, grant.id)
      editor |> click_button("Publish saved draft") |> assert_path("/manage/groups")

      c.conn
      |> visit("/toronto")
      |> assert_path("/groups/toronto")
      |> assert_has("h1", text: "Toronto")
      |> assert_has("h2", text: "Toronto meetups")
      |> assert_has("strong", text: "local volunteers")
      |> assert_has("article img[src$='toronto-crossing.jpg']")
      |> refute_has("p", text: "Private changes")
      |> PhoenixTest.Playwright.screenshot("chapter-published.png")
    end

    @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
    test "French visitor reaches a published chapter from the directory", c do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      admin =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()
        |> Accounts.Scope.for_user()

      {:ok, group} = Volunteers.create_group(admin, %{name: "Ottawa"})

      {:ok, profile} =
        Incubators.configure(admin, group.id, %{
          "name_en" => "Ottawa",
          "name_fr" => "Ottawa",
          "summary_fr" => "Le groupe local à Ottawa",
          "published" => true
        })

      {:ok, draft} =
        Incubators.save_chapter(admin, group.id, profile.revision, %{
          "slug" => "ottawa",
          "en" => "Ottawa welcome",
          "fr" => ""
        })

      {:ok, _} = Incubators.publish_chapter(admin, group.id, draft.revision)

      ga = Application.get_env(:pauseai_ca, :ga_measurement_id)
      Application.put_env(:pauseai_ca, :ga_measurement_id, "G-ATDDLOCAL")
      on_exit(fn -> Application.put_env(:pauseai_ca, :ga_measurement_id, ga) end)

      {:ok, _} =
        PlaywrightEx.BrowserContext.add_init_script(c.conn.context_id,
          timeout: 5000,
          source: """
          const append = Node.prototype.appendChild;
          Node.prototype.appendChild = function(node) {
            if(node.tagName === 'SCRIPT' && node.src.includes('googletagmanager.com')) node.removeAttribute('src');
            return append.call(this, node);
          };
          """
        )

      c.conn
      |> visit("/groupes")
      |> assert_path("/fr/groupes")
      |> click_link("Visiter la page du groupe")
      |> assert_has("h1", text: "Ottawa")
      |> assert_has("[lang=en] p", text: "Ottawa welcome")
      |> PhoenixTest.Playwright.click("#consent-decline")
      |> refute_has("#ga-script")
      |> PhoenixTest.Playwright.screenshot("chapter-phone-fr.png")
      |> PhoenixTest.Playwright.evaluate(
        "localStorage.removeItem('pauseai-ca:analytics-consent')"
      )
      |> visit("/groups/ottawa?locale=fr&private=example")
      |> PhoenixTest.Playwright.click("#consent-accept")
      |> PhoenixTest.Playwright.evaluate(
        "window.dataLayer.filter(x=>x[1]==='page_view').map(x=>x[2].page_location)",
        fn urls ->
          assert [url] = urls
          assert String.ends_with?(url, "/groups/ottawa")
        end
      )
    end

    defp login(browser, user) do
      {token, _} = generate_user_magic_link_token(user)

      browser
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end
  end
end
