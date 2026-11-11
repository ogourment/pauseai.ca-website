if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.VancouverGuidedTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Assistant, CRM, GuidedModeFixtures, Newsletters, Repo}
    alias PauseAiCa.Assistant.VancouverGuide
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios for {locale, language, device} <- [
                     {"en", "English", "Desktop"},
                     {"fr", "French", "Phone"}
                   ],
                   do: %{
                     id: "CRM-UX-VAN-01-#{locale}",
                     title:
                       "Vancouver source reference, city list and unsent draft · #{language}",
                     roles: ["Superadmin"],
                     language: language,
                     device: device,
                     source_file: __ENV__.file
                   }

    defmodule Provider do
      defdelegate input_token_bound(request, mode, options),
        to: PauseAiCa.AssistantFixtures.Provider

      def generate(request, mode, options) do
        send(options[:observer], {:vancouver_fixture_called, request})
        manifest = Jason.decode!(request["context"]["guided_mode"]["manifest_json"])

        {:ok,
         %{
           "text" => Jason.encode!(VancouverGuide.example_plan(manifest)),
           "model" => mode.model,
           "usage" => %{"input_tokens" => 100, "output_tokens" => 100}
         }}
      end
    end

    setup_all do
      AtddEvidence.reset!("CRM-UX-VAN-01 · human-paced Vancouver workflow", @scenarios, %{
        browser: "Chromium",
        fixture: "Synthetic provider, contacts and newsletter consent only"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "CRM-UX-VAN-01 source-backed city workflow #{locale}", c do
        locale = unquote(locale)
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        previous = Application.fetch_env(:pauseai_ca, :agent_assistant)

        environment =
          Map.new(~w(PAUSEAI_CA_RELEASE_ID PAUSEAI_CA_GIT_SHA), &{&1, System.get_env(&1)})

        System.put_env("PAUSEAI_CA_RELEASE_ID", "guided-synthetic-fixture")
        System.put_env("PAUSEAI_CA_GIT_SHA", String.duplicate("a", 40))

        config =
          GuidedModeFixtures.configuration(self())
          |> Keyword.put(:provider, {Provider, [api_key: "synthetic-fixture", observer: self()]})
          |> Keyword.update!(
            :features,
            &(&1 ++
                [
                  %{
                    id: "crm-vancouver-guided",
                    title: "Vancouver workflow",
                    summary: "Fixture",
                    introduced_in: Application.spec(:pauseai_ca, :vsn) |> to_string(),
                    entry_path: "/admin/contacts",
                    enabled: true,
                    ready: true,
                    scenarios: ["CRM-UX-VAN-01-en", "CRM-UX-VAN-01-fr"]
                  }
                ])
          )
          |> Keyword.update!(:feature_evidence, fn evidence ->
            update_in(
              evidence,
              [:results],
              &Map.merge(&1, %{"CRM-UX-VAN-01-en" => "success", "CRM-UX-VAN-01-fr" => "success"})
            )
          end)

        Application.put_env(:pauseai_ca, :agent_assistant, config)

        on_exit(fn ->
          case previous do
            {:ok, value} -> Application.put_env(:pauseai_ca, :agent_assistant, value)
            :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
          end

          for {key, value} <- environment do
            if value, do: System.put_env(key, value), else: System.delete_env(key)
          end
        end)

        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        scope = Accounts.Scope.for_user(admin)
        {:ok, _} = Assistant.set_enabled(scope, true)

        {:ok, vancouver} =
          CRM.create(scope, %{
            name: "Synthetic Vancouver",
            email: "vancouver-guide@example.org",
            city: "Vancouver"
          })

        {:ok, outside} =
          CRM.create(scope, %{
            name: "Synthetic Burnaby",
            email: "burnaby-guide@example.org",
            city: "Burnaby"
          })

        {:ok, signup} =
          Newsletters.request_signup("vancouver-guide@example.org", %{
            consent: true,
            city: "Vancouver"
          })

        {:ok, _} = Newsletters.confirm(signup.confirmation_token)
        {token, _} = generate_user_magic_link_token(admin)
        list_name = "Synthetic Vancouver #{locale}"
        subject = "Synthetic Vancouver invitation · Invitation fictive à Vancouver"

        invitation = """
        ## Help start a Vancouver incubator

        This synthetic invitation is for review. Choose the Vancouver waitlist or offer to help.

        [Join the Vancouver waitlist](https://pauseai.ca/en/participate?intent=waitlist&city=Vancouver)

        [I can help in Vancouver](https://pauseai.ca/en/participate?intent=help&city=Vancouver)

        ## Aidez à lancer un incubateur à Vancouver

        Cette invitation fictive est destinée à la révision. Inscrivez-vous à la liste d’attente ou proposez votre aide.

        [Liste d’attente de Vancouver](https://pauseai.ca/fr/participer?intent=waitlist&city=Vancouver)

        [Je peux aider à Vancouver](https://pauseai.ca/fr/participer?intent=help&city=Vancouver)
        """

        b =
          c.conn
          |> visit("/users/log-in/#{token}?locale=#{locale}")
          |> click_button(tr(locale, "Keep me logged in on this device"))
          |> assert_path("/")
          |> assert_has("#account-menu")
          |> visit("/admin/assistant?locale=#{locale}")
          |> assert_has(".phx-connected #site-assistant-launcher")
          |> click_button("#site-assistant-launcher", tr(locale, "Assistant"))
          |> check(tr(locale, "Guided mode"))
          |> fill_in("#site-assistant-text", tr(locale, "Message"),
            with:
              "Show Vancouver FSA sources, preview city contacts, then help me prepare a list and unsent newsletter draft."
          )
          |> capture(
            locale,
            "Guided mode entry",
            "Open Assistant, choose Guided mode and enter the Vancouver request"
          )
          |> click_button("#site-assistant-form button[type=submit]", tr(locale, "Send"))
          |> assert_has("#site-assistant-guide-step",
            text: tr(locale, "Step 1 of 5 · Open Contacts.")
          )
          |> PhoenixTest.Playwright.click("#vancouver-guide-reference summary")
          |> assert_has("#vancouver-guide-reference[open]", text: "V7Y")
          |> capture(
            locale,
            "Pinned public reference and reviewed guide",
            "Send the single synthetic fixture request, then open the postal reference"
          )
          |> click_button("#site-assistant-guide-next", tr(locale, "Next"))
          |> assert_has("#crm-directory")
          |> assert_has("#site-assistant-guide-step",
            text: tr(locale, "Step 2 of 5 · Choose Vancouver in Cities and preview the matches.")
          )
          |> click_button("#site-assistant-guide-next", tr(locale, "Next"))
          |> assert_has("#crm-contact-#{vancouver.person.id}")
          |> refute_has("#crm-contact-#{outside.person.id}")
          |> assert_has("#site-assistant-guide-step",
            text: tr(locale, "Step 3 of 5 · Open Lists.")
          )
          |> capture(
            locale,
            "Actual Vancouver city preview",
            "Next opens Contacts; Next selects the registered Vancouver city value"
          )
          |> click_button("#site-assistant-guide-next", tr(locale, "Next"))
          |> assert_has("#contact-lists")
          |> assert_has("#site-assistant-guide-step",
            text:
              tr(
                locale,
                "Step 4 of 5 · Name a dynamic list, set city to Vancouver, then choose Save list."
              )
          )
          |> click_button("#site-assistant-guide-next", tr(locale, "Next"))
          |> fill_in("#list_name", tr(locale, "Name"), with: list_name)
          |> fill_in("#list_city", tr(locale, "Cities"), with: "Vancouver")
          |> capture(
            locale,
            "Human-reviewed dynamic city list",
            "Next highlights List name; the human enters name and city"
          )
          |> click_button("#contact-list-save", tr(locale, "Save list"))
          |> assert_has("#selected-contact-list", text: list_name)
          |> assert_has("#site-assistant-guide-step",
            text:
              tr(locale, "Step 5 of 5 · Review the saved list, then choose Compose newsletter.")
          )
          |> click_button("#site-assistant-guide-next", tr(locale, "Next"))
          |> capture(
            locale,
            "Saved list and explicit Compose",
            "Human Save list; Next highlights Compose newsletter"
          )
          |> click_button("#contact-list-compose-newsletter", tr(locale, "Compose newsletter"))
          |> assert_has("#newsletter-draft")
          |> assert_has("#site-assistant-guide-step",
            text:
              tr(locale, "Complete · Your newsletter draft is open for review. Nothing was sent.")
          )
          |> click_button("#site-assistant-guide-exit", tr(locale, "Exit"))
          |> click_link("#email-write-message", tr(locale, "Write message"), exact: true)
          |> fill_in(tr(locale, "Subject"), with: subject)
          |> fill_in(tr(locale, "Message · Markdown"), with: invitation)
          |> assert_has("#newsletter-save-status",
            text: tr(locale, "Unsaved changes"),
            exact: true
          )
          |> click_button("#newsletter-draft-form button", tr(locale, "Save"), exact: true)
          |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)
          |> capture(
            locale,
            "Saved invitation in the shared editor",
            "Exit guide, choose Write message, enter the invitation and click Save"
          )
          |> click_button("#email-review-send", tr(locale, "Review & send"), exact: true)
          |> assert_has("#newsletter-batch-review",
            text: tr(locale, "Message and recipients to send")
          )
          |> assert_has("#newsletter-batch-review", text: "vancouver-guide@example.org")
          |> assert_has("#newsletter-batch-review", text: subject)
          |> assert_has(
            "#newsletter-batch-review a[href='https://pauseai.ca/en/participate?intent=waitlist&city=Vancouver']"
          )
          |> assert_has(
            "#newsletter-batch-review a[href='https://pauseai.ca/en/participate?intent=help&city=Vancouver']"
          )
          |> capture(
            locale,
            "Complete invitation and recipient review · unsent",
            "Human writes the synthetic invitation, clicks Save, then Review & send; stops before Send now"
          )

        assert_received {:vancouver_fixture_called, request}

        assert length(request["context"]["canadian_references"]["vancouver"]["candidate_fsas"]) ==
                 31

        refute_received {:vancouver_fixture_called, _}
        assert Repo.aggregate(Newsletters.Draft, :count) == 1
        assert [draft] = Repo.all(Newsletters.Draft)
        assert draft.source == invitation && draft.subject == subject
        assert [batch] = Repo.all(Newsletters.Batch)
        assert batch.state == "review" && is_nil(batch.approved_at) && is_nil(batch.approver_id)
        assert batch.source == invitation && batch.subject == subject

        assert batch.recipient_keys == [
                 Repo.get_by!(Newsletters.Subscription, email: "vancouver-guide@example.org").id
               ]

        assert [delivery] = Repo.all(Newsletters.Delivery)
        assert delivery.state == "pending" && is_nil(delivery.attempted_at)
        assert is_nil(delivery.accepted_at) && is_nil(delivery.provider_id)
        assert b

        AtddEvidence.mark_scenario_success!(
          Enum.find(@scenarios, &(&1.id == "CRM-UX-VAN-01-#{locale}"))
        )
      end
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(b, locale, screen, control) do
      PhoenixTest.Playwright.evaluate(
        b,
        "document.documentElement.scrollWidth <= innerWidth",
        &assert(&1)
      )

      sid = "CRM-UX-VAN-01-#{locale}"
      step = Process.get({:vancouver_step, locale}, 0) + 1
      Process.put({:vancouver_step, locale}, step)
      filename = "#{sid}-#{step}.png"
      PhoenixTest.Playwright.evaluate(b, "location.href", &Process.put(:vancouver_url, &1))
      url = AtddEvidence.safe_url(Process.get(:vancouver_url))
      IO.puts("Capture URL: #{url}")

      metadata = %{
        "scenario_id" => sid,
        "url" => url,
        "control" => control,
        "preceding_screen" => Process.get({:vancouver_screen, locale}, "Assistant settings"),
        "source" =>
          "Actual local synthetic fixture journey; one fixture generation; no provider network or outgoing email"
      }

      AcceptanceHarness.Evidence.record_pending_step(filename, screen, control, metadata)
      b = AtddEvidence.capture_full_page(b, filename)

      AtddEvidence.record_step(
        filename,
        screen,
        control,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(b)))
      )

      Process.put({:vancouver_screen, locale}, screen)
      b
    end
  end
end
