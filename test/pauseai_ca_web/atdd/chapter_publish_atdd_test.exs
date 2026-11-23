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
          "area_served" => "local",
          "fsas" => "H2X",
          "published" => true
        })

      :ok = PlaywrightEx.subscribe(c.conn.context_id)

      editor =
        c.conn
        |> login(manager)
        |> visit("/manage/groups?group=#{group.id}")
        |> PhoenixTest.Playwright.click("nav a[href*='tab=settings']")
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
            preview = LazyHTML.from_document(html)
            assert preview |> LazyHTML.query("h2") |> LazyHTML.text() == "Toronto meetups"
            assert preview |> LazyHTML.query("strong") |> LazyHTML.text() == "local volunteers"

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

      assert_initial_title("/groups/toronto?locale=en", "Toronto")

      c.conn
      |> visit("/toronto")
      |> assert_path("/groups/toronto")
      |> assert_has("[data-phx-main].phx-connected")
      |> PhoenixTest.Playwright.evaluate("document.title", &assert(&1 == "Toronto"))
      |> assert_has("h1", text: "Toronto")
      |> assert_has("h2", text: "Toronto meetups")
      |> assert_has("strong", text: "local volunteers")
      |> assert_has("article img[src$='toronto-crossing.jpg']")
      |> assert_has("figure figcaption", text: "PauseAI Toronto")
      |> PhoenixTest.Playwright.evaluate(
        "document.querySelector('article figure').getBoundingClientRect().left >= document.querySelector('article h1').getBoundingClientRect().right",
        &assert(&1)
      )
      |> refute_has("p", text: "Private changes")
      |> PhoenixTest.Playwright.screenshot("chapter-published.png")

      assert %{id: _} =
               PlaywrightEx.send(
                 %{
                   guid: c.conn.page_id,
                   method: :set_viewport_size,
                   params: %{viewport_size: %{width: 390, height: 844}}
                 },
                 timeout: 5000
               )

      c.conn
      |> PhoenixTest.Playwright.evaluate(
        "innerWidth === 390 && document.documentElement.scrollWidth <= innerWidth && document.querySelector('article figure').getBoundingClientRect().top >= document.querySelector('article a').getBoundingClientRect().bottom",
        &assert(&1)
      )
      |> PhoenixTest.Playwright.screenshot("chapter-photo-phone.png")
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
          "name_fr" => "Groupe d’Ottawa",
          "summary_fr" => "Le groupe local à Ottawa",
          "area_served" => "local",
          "fsas" => "H2X",
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

      assert_initial_title("/groups/ottawa?locale=fr", "Groupe d’Ottawa")

      c.conn
      |> visit("/groupes")
      |> assert_path("/fr/groupes")
      |> click_link("Visiter la page du groupe")
      |> assert_has("[data-phx-main].phx-connected")
      |> PhoenixTest.Playwright.evaluate("document.title", &assert(&1 == "Groupe d’Ottawa"))
      |> assert_has("h1", text: "Groupe d’Ottawa")
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

    @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
    test "Toronto reserves portrait space and opens its legacy letter bookmark", c do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      admin =
        user_fixture()
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()
        |> Accounts.Scope.for_user()

      {:ok, group} = Volunteers.create_group(admin, %{name: "Toronto"})

      {:ok, profile} =
        Incubators.configure(admin, group.id, %{
          "name_en" => "Toronto",
          "name_fr" => "Toronto",
          "area_served" => "local",
          "fsas" => "M5H",
          "published" => true
        })

      source = """
      # Welcome to Toronto

      ## Team

      ![Muhammad](/images/toronto-site/muhammad.jpg)
      ![Daniel](/images/toronto-site/daniel.jpg)
      ![Ilyass](/images/toronto-site/ilyass.jpg)

      ## Shop

      - [![Toronto cap](/images/toronto-site/shop/pauseai-cap.jpg) Toronto cap](https://example.org)
      """

      {:ok, draft} =
        Incubators.save_chapter(admin, group.id, profile.revision, %{
          "slug" => "toronto",
          "en" => source,
          "fr" => ""
        })

      {:ok, _} = Incubators.publish_chapter(admin, group.id, draft.revision)

      {:ok, page} =
        Incubators.save_chapter_page(admin, group.id, nil, 0, %{
          "slug" => "write-to-your-mp",
          "title" => "Write to your MP",
          "body" => "Write to your representative."
        })

      {:ok, _} = Incubators.publish_chapter_page(admin, group.id, page.slug, page.revision)

      c.conn
      |> visit("/toronto")
      |> assert_has(~s(img[alt="Muhammad"][width="560"][height="560"]))
      |> assert_has(~s(img[alt="Daniel"][width="480"][height="480"]))
      |> assert_has(~s(img[alt="Ilyass"][width="480"][height="480"]))
      |> PhoenixTest.Playwright.evaluate(
        ~s|getComputedStyle(document.querySelector('img[alt="Toronto cap"]')).display|,
        &assert(&1 == "block")
      )
      |> visit("/groups/toronto/pages/write-to-your-mp?riding=toronto-centre#letter")
      |> assert_has("[data-phx-main].phx-connected")
      |> assert_has("#letter:not([hidden]) label[for='toronto-letter']", text: "Your letter")
      |> PhoenixTest.Playwright.evaluate(
        """
        new Promise(resolve => requestAnimationFrame(() => {
          const composer = document.querySelector('#letter');
          const letter = composer.querySelector('#toronto-letter');
          const stickyBottom = Math.max(...['site-header', 'announcement-banners']
            .map(id => document.getElementById(id)?.getBoundingClientRect().bottom || 0));
          const top = composer.getBoundingClientRect().top;
          resolve(location.hash === '#letter' && letter.value.includes('Toronto Centre')
            && top >= stickyBottom && top < innerHeight);
        }))
        """,
        &assert(&1)
      )
      |> PhoenixTest.Playwright.screenshot("chapter-bookmarked-letter-phone.png")
    end

    defp assert_initial_title(path, title) do
      base = Application.fetch_env!(:phoenix_test, :base_url)
      %{status: 200, body: html} = Req.get!(base <> path)

      assert html |> LazyHTML.from_document() |> LazyHTML.query("title") |> LazyHTML.text() ==
               title
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
