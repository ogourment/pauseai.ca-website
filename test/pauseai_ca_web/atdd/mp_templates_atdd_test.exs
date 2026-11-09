if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.MPTemplatesTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    import PauseAiCa.MPTemplatesFixtures
    alias PauseAiCa.{Accounts, MPTemplates, Repo}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "CRM-ASSIST-GUIDE-03-CMS-#{locale}",
                     title:
                       "Author-permitted campaign template and independent friends · #{language}",
                     roles: ["Superadmin editor", "Confirmed supporter", "Separate friend"],
                     language: language,
                     device: device,
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!("CRM-ASSIST-GUIDE-03 · campaign CMS and shared editions", @scenarios, %{
        fixture: "Synthetic campaign text and separate accounts; local browser and database only"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-ASSIST-GUIDE-03-CMS-#{locale} reviewed publication and private independent identities",
           c do
        locale = unquote(locale)
        id = "CRM-ASSIST-GUIDE-03-CMS-#{locale}"
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        editor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        supporter = user_fixture(%{email: "synthetic-campaign-supporter@example.org"})
        friend = user_fixture(%{email: "synthetic-campaign-friend@example.org"})
        scope = Accounts.Scope.for_user(editor)
        payload = mp_template_payload()
        slug = "synthetic-shared-campaign-#{locale}"
        flush_mail()
        before = counts()

        browser =
          c.conn
          |> login(editor)
          |> visit("/manage/accounts?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected")
          |> PauseAiCaWeb.AtddNavigation.open_section("manage")
          |> click_link(tr(locale, "MP letter templates"))
          |> assert_has("[data-phx-main].phx-connected #mp-template-create")
          |> fill_in("#mp-template-create input", tr(locale, "Campaign slug"), with: slug)
          |> click_button(tr(locale, "Create template"))
          |> assert_has("#mp-template-editor")
          |> fill_in("#mp-template-author", tr(locale, "Public author attribution"),
            with: payload["author"]
          )
          |> fill_in("#mp-template-source", tr(locale, "Public source URL"),
            with: payload["source"]
          )

        browser =
          Enum.reduce(~w(en fr), browser, fn language, browser ->
            edition = payload["editions"][language]

            browser
            |> fill_in("#mp-template-#{language}-title", tr(locale, "Campaign title"),
              with: edition["title"]
            )
            |> fill_in("#mp-template-#{language}-purpose", tr(locale, "Campaign purpose"),
              with: edition["purpose"]
            )
            |> fill_in("#mp-template-#{language}-subject", tr(locale, "Letter subject"),
              with: edition["subject"]
            )
            |> fill_in(
              "#mp-template-#{language}-body-source",
              tr(locale, "Letter body · Markdown"),
              with: edition["body"]
            )
          end)

        browser =
          browser
          |> click_button("#mp-template-form button", tr(locale, "Save draft"))
          |> assert_has("#mp-template-status", text: tr(locale, "Draft saved"), exact: true)
          |> capture(
            id,
            "Saved bilingual campaign draft",
            "Management → MP letter templates",
            "Create template; fill both editions; Save draft"
          )

        assert {:ok, [template]} = MPTemplates.list(scope)
        assert {:error, :not_found} = MPTemplates.published(slug, locale)

        browser =
          browser
          |> visit("/manage/mp-templates/#{template.id}?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected #mp-template-editor")
          |> assert_has("#mp-template-en-title", value: payload["editions"]["en"]["title"])
          |> assert_has("#mp-template-fr-title", value: payload["editions"]["fr"]["title"])
          |> click_button(tr(locale, "Publish campaign template"))
          |> assert_has("#mp-template-error",
            text: tr(locale, "Confirm the author's permission for this publication."),
            exact: true
          )
          |> check(tr(locale, "I have the author's permission to publish this template."))
          |> click_button(tr(locale, "Publish campaign template"))
          |> assert_has("#mp-template-status",
            text: tr(locale, "Campaign template published"),
            exact: true
          )
          |> capture(
            id,
            "Explicit author-permitted publication",
            "Reloaded saved bilingual draft",
            "Publish; acknowledge author permission; Publish campaign template"
          )

        {:ok, campaign} = MPTemplates.published(slug, locale)

        assert URI.decode_query(URI.parse(campaign.share_path).query) == %{
                 "revision" => to_string(campaign.revision)
               }

        refute campaign.share_path =~ supporter.email
        refute campaign.share_path =~ friend.email
        assert {:ok, history} = MPTemplates.history(scope, template)
        assert hd(history).editor_id == editor.id
        assert hd(history).author_permission

        browser =
          browser
          |> switch_browser_identity(&login(&1, supporter))
          |> visit(campaign.share_path)
          |> assert_has("[data-phx-main].phx-connected #mp-campaign-template")
          |> assert_has("#mp-template-purpose", text: campaign.purpose, exact: true)
          |> assert_has("#mp-template-author", text: payload["author"], exact: true)
          |> assert_has("#mp-template-source[href='#{payload["source"]}']")
          |> assert_has("#mp-template-personalize",
            text: tr(locale, "Personalize this letter"),
            exact: true
          )
          |> capture(
            id,
            "Original supporter's shared public edition",
            "Confirmed synthetic supporter on their own account",
            "Open the frozen published website link"
          )
          |> switch_browser_identity(&login(&1, friend))
          |> visit(campaign.share_path)
          |> assert_has("[data-phx-main].phx-connected #mp-campaign-template")
          |> assert_has("#mp-template-public-body", text: campaign.body, exact: true)
          |> refute_has("body", text: supporter.email)
          |> capture(
            id,
            "Separate friend opens the shared campaign",
            "Separate confirmed friend's own browser identity",
            "Open the shared website link"
          )

        evaluate(
          browser,
          "document.querySelector('#mp-template-personalize').getAttribute('href')",
          fn path ->
            uri = URI.parse(path)

            assert URI.decode_query(uri.query) == %{
                     "template" => slug,
                     "revision" => to_string(campaign.revision)
                   }

            refute path =~ "@"
          end
        )

        assert counts() == before
        refute_received {:email, _}
        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
        browser
      end
    end

    defp counts,
      do: %{
        actions: Repo.aggregate(PauseAiCa.Engagement.Action, :count),
        subscriptions: Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count),
        deliveries: Repo.aggregate(PauseAiCa.Newsletters.Delivery, :count)
      }

    defp login(browser, user) do
      {token, _} = generate_user_magic_link_token(user)

      browser
      |> visit("/users/log-in/#{token}?locale=en")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp flush_mail do
      receive do
        {:email, _} -> flush_mail()
      after
        0 -> :ok
      end
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, id, title, preceding, control) do
      evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      step = Process.get({:mp_template_step, id}, 0) + 1
      Process.put({:mp_template_step, id}, step)
      filename = "#{id}-#{step}.png"
      evaluate(browser, "location.href", &Process.put(:mp_template_capture_url, &1))
      url = AtddEvidence.safe_url(Process.get(:mp_template_capture_url))
      IO.puts("Capture URL: #{url}")

      metadata = %{
        "scenario_id" => id,
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "fixture" =>
          "Synthetic campaign and separate identities; no actual letters or source drafts"
      }

      AcceptanceHarness.Evidence.record_pending_step(
        filename,
        title,
        "CMS-reviewed campaign publication and independent public readership",
        metadata
      )

      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        title,
        "CMS-reviewed campaign publication and independent public readership",
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
