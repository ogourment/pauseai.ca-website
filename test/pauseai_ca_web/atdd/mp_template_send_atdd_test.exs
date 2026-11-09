if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.MPTemplateSendTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    import PauseAiCa.MPTemplatesFixtures
    alias PauseAiCa.{Accounts, Engagement, MPTemplates, Repo}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "CRM-ASSIST-GUIDE-03-#{locale}",
                     title: "Friend independently personalizes and sends a published template",
                     roles: ["Original supporter", "Independent confirmed friend"],
                     language: language,
                     device: device,
                     source_file: __ENV__.file
                   }

    setup_all do
      AtddEvidence.reset!("Friends own their campaign letters and actions", @scenarios, %{
        fixture:
          "Author-permitted synthetic template, separate browser identities, Represent stub and local mail"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

      previous = [
        {:pauseai_ca, :mp_guide_enabled, Application.fetch_env(:pauseai_ca, :mp_guide_enabled)},
        {:swoosh, :shared_test_process, Application.fetch_env(:swoosh, :shared_test_process)}
      ]

      Application.put_env(:pauseai_ca, :mp_guide_enabled, true)
      Application.put_env(:swoosh, :shared_test_process, self())

      on_exit(fn ->
        for {app, key, saved} <- previous do
          case saved do
            {:ok, value} -> Application.put_env(app, key, value)
            :error -> Application.delete_env(app, key)
          end
        end
      end)

      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-ASSIST-GUIDE-03 independent friend sends own published campaign letter #{locale}",
           c do
        journey(c, unquote(locale), unquote(width), unquote(height))
      end
    end

    defp journey(c, locale, width, height) do
      editor = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

      {:ok, draft} =
        MPTemplates.create(Accounts.Scope.for_user(editor), "friend-campaign-#{locale}")

      {:ok, saved} =
        MPTemplates.save(Accounts.Scope.for_user(editor), draft, mp_template_payload())

      {:ok, published} = MPTemplates.publish(Accounts.Scope.for_user(editor), saved, true)
      {:ok, edition} = MPTemplates.published(published.slug, locale, published.revision)
      original = user_fixture()
      original_scope = Accounts.Scope.for_user(original)
      baseline = length(Engagement.list_actions(original_scope))
      requests = Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count)
      count = MPTemplates.completed_count(published.id)
      id = "CRM-ASSIST-GUIDE-03-" <> locale
      {token, _} = generate_user_magic_link_token(original)
      # Account factories emit synthetic marker emails while confirming users.
      # The next receive must belong to the friend's actual sign-in request.
      flush_mail()

      original_browser =
        c.conn
        |> visit("/users/log-in/#{token}?locale=#{locale}")
        |> click_button(tr(locale, "Keep me logged in on this device"))
        |> assert_path("/")
        |> assert_has("#account-menu")
        |> visit(edition.share_path)
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#mp-template-purpose", text: edition.purpose)
        |> assert_has("#mp-template-share")
        |> capture(
          id,
          "Published link shared",
          "Original supporter's public campaign preview",
          "Share this published version",
          "Only the immutable campaign slug and revision are shared. No original letter, account, sender or postal code is included."
        )

      evaluate(
        original_browser,
        "document.querySelector('#mp-template-share').getAttribute('href')",
        fn path ->
          assert path == edition.share_path
          refute path =~ original.email
          refute path =~ original.id

          assert URI.decode_query(URI.parse(path).query) == %{
                   "revision" => to_string(published.revision)
                 }
        end
      )

      browser =
        PhoenixTest.Playwright.Case.new_session(
          PhoenixTest.Playwright.Config.validate!(
            browser_context_opts: [viewport: %{width: width, height: height}]
          ),
          c
        )

      assert browser.context_id != original_browser.context_id
      friend_email = "independent-friend-#{locale}@example.invalid"

      browser =
        browser
        |> visit(edition.share_path)
        |> assert_has("#mp-template-public-revision", text: to_string(published.revision))
        |> click_link("#mp-template-personalize", tr(locale, "Personalize this letter"))
        |> assert_has("[data-phx-main].phx-connected")
        |> click_button("#mp-guide-start", tr(locale, "Guide me through this"))
        |> assert_has("#mp-guide-sign-in")
        |> click_link("#mp-guide-sign-in a", tr(locale, "Sign in"))
        |> fill_in("#login_form_magic_email", tr(locale, "Email"), with: friend_email)
        |> click_button(tr(locale, "Email me a secure link"))
        |> assert_has("#account-email-pending")

      assert_receive {:email, %Swoosh.Email{to: [{_, ^friend_email}]} = login_mail}
      [url] = Regex.run(~r{https?://[^\s<>]+/users/log-in/[^\s<>]+}, login_mail.text_body)
      parsed = URI.parse(url)

      browser =
        browser
        |> visit(parsed.path <> "?" <> parsed.query)
        |> assert_has("#confirmation_form")
        |> click_button(tr(locale, "Confirm and stay logged in"))
        |> assert_path(PauseAiCa.Assistant.MPGuide.path(locale),
          query_params: %{
            guide: "1",
            template: published.slug,
            revision: to_string(published.revision)
          }
        )
        |> assert_has("#account-menu")
        |> assert_has("[data-phx-main].phx-connected")
        |> assert_has("#mp-guide-next")
        |> refute_has("#site-assistant-launcher")
        |> capture(
          id,
          "Friend confirms own account",
          "Friend sign-in prerequisite",
          "Email me a secure link, then confirm own link",
          "The friend returns to the same frozen template with their own confirmed ordinary account. No subscription or organizer powers are granted."
        )

      friend = Accounts.get_user_by_email(friend_email)
      assert friend.confirmed_at
      refute friend.superadmin
      friend_scope = Accounts.Scope.for_user(friend)

      browser =
        browser
        |> click_button("#mp-guide-next", tr(locale, "Next"))
        |> assert_has("#participation_postal_code:focus")
        |> fill_in("#participation_name", tr(locale, "Name"),
          with: "Independent Synthetic Friend"
        )
        |> fill_in("#participation_postal_code", tr(locale, "Postal code"), with: "H2X 1Y4")
        |> uncheck(tr(locale, "Subscribe me to the PauseAI Canada newsletter."))
        |> click_button("#participation-submit", tr(locale, "Continue to my letter"))
        |> assert_has("#mp-results", text: "Steven Guilbeault")
        |> assert_has("#letter-form")
        |> assert_has("#mp-guide-step",
          text:
            tr(
              locale,
              "Paste and personalize your subject and letter. Replace every remaining placeholder, then choose Next."
            )
        )

      flush_mail()

      body =
        "Private synthetic friend wording #{locale}. I am writing personally about this published campaign."

      browser =
        browser
        |> fill_in("#letter_subject", tr(locale, "Subject"),
          with: "Independent friend's own subject"
        )
        |> fill_in("#letter_body", tr(locale, "Body"), with: body)
        |> click_button("#mp-guide-next", tr(locale, "Next"))
        |> assert_has("#mp-guide-step",
          text:
            tr(
              locale,
              "Review the actual MP, sender, subject and letter. You choose the authorization box and Send. The guide cannot send for you."
            )
        )
        |> click_button("#mp-guide-next", tr(locale, "Next"))
        |> assert_has("#send-letter:focus")
        |> evaluate("document.activeElement.id", &assert(&1 == "send-letter"))
        |> capture(
          id,
          "Friend reviews own letter",
          "Own representative lookup and personalized editor",
          "Next highlights the existing Send control",
          "The friend reviews their own sender, MP and words. The guide has not sent anything or recorded an action."
        )

      assert Engagement.list_actions(friend_scope) == []

      browser =
        browser
        |> check(tr(locale, "I authorize PauseAI Canada to send this letter to my MP."))
        |> click_button("#send-letter", tr(locale, "Send the letter"))
        |> assert_has("#send-success")
        |> assert_has("#mp-guide-step",
          text:
            tr(
              locale,
              "Your sent letter is recorded in your account. This confirms the website outcome, not that your MP has read it."
            )
        )

      assert_receive {:email, sent}
      assert sent.text_body =~ body
      assert Enum.any?(sent.to, fn {_, address} -> address == friend_email end)
      [action] = Engagement.list_actions(friend_scope)
      assert action.confirmed_at
      assert MPTemplates.completed_count(published.id) == count + 1

      browser =
        browser
        |> click_button("#send-letter", tr(locale, "Send the letter"))
        |> assert_has("#send-success")
        |> click_button("#mp-guide-exit", tr(locale, "Exit"))
        |> refute_has("#mp-guide")
        |> visit(dashboard(locale))
        |> assert_has("#actions-#{action.id}")
        |> visit(dashboard(locale))
        |> assert_has("#actions-#{action.id}")
        |> capture(
          id,
          "Friend owns the persistent action",
          "Successful synthetic delivery",
          "Open dashboard and reload",
          "The same confirmed action remains in the friend's account. Duplicate sending creates no second letter or campaign total."
        )

      assert length(Engagement.list_actions(friend_scope)) == 1
      assert MPTemplates.completed_count(published.id) == count + 1

      original_browser =
        original_browser
        |> visit(dashboard(locale))
        |> refute_has("#actions-#{action.id}")
        |> refute_has("body", text: friend_email)
        |> refute_has("body", text: body)
        |> capture(
          id,
          "Original account remains private",
          "Original supporter returns independently",
          "Open own dashboard",
          "The original supporter's count is unchanged and the friend's letter, email and action history are absent."
        )

      assert length(Engagement.list_actions(original_scope)) == baseline

      original_browser =
        original_browser
        |> visit(edition.share_path)
        |> assert_has("#mp-template-completed-count", text: to_string(count + 1))
        |> refute_has("body", text: friend_email)
        |> refute_has("body", text: body)
        |> capture(
          id,
          "Aggregate campaign result",
          "Public immutable campaign preview",
          "Reload shared campaign page",
          "The public count increases once without identifying either supporter or attributing a referral."
        )

      assert Repo.aggregate(PauseAiCa.Newsletters.Subscription, :count) == 0
      assert Repo.aggregate(PhoenixAgentAssistant.Store.Request, :count) == requests
      refute_receive {:email, _}
      AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
      {browser, original_browser}
    end

    defp dashboard("fr"), do: "/fr/tableau-de-bord"
    defp dashboard(_), do: "/en/dashboard"

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

    defp capture(browser, id, title, preceding, control, description) do
      evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      evaluate(browser, "location.href", &Process.put(:mp_friend_url, &1))
      url = AtddEvidence.safe_url(Process.get(:mp_friend_url))
      IO.puts("Capture URL: #{url}")
      step = Process.get({:mp_friend_capture, id}, 0) + 1
      Process.put({:mp_friend_capture, id}, step)
      file = "#{id}-#{step}.png"

      metadata = %{
        "scenario_id" => id,
        "url" => url,
        "preceding_screen" => preceding,
        "control" => control,
        "fixture" => "Synthetic author-permitted template and independent ordinary accounts"
      }

      AcceptanceHarness.Evidence.record_pending_step(file, title, description, metadata)
      browser = AtddEvidence.capture_full_page(browser, file)

      AtddEvidence.record_step(
        file,
        title,
        description,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
