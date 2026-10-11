if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.NamedListsTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Newsletters, Repo}
    alias PauseAiCa.Newsletters.{Lists, Drafts, Batches, Delivery}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "LIST-NEWS-01-#{locale}",
                    title: "Dynamic mailing lists and whole-list review · #{language}",
                    tags: ["newsletter", "mail", "superadmin"],
                    roles: ["Superadmin"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!(
        "LIST-NEWS-01 · dynamic geography and whole-list composition",
        @scenarios,
        %{browser: "Chromium", viewport: "Desktop and phone"}
      )

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "LIST-NEWS-01 dynamic list journey #{locale}", c do
        journey(c, unquote(locale))
      end
    end

    defp journey(c, locale) do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
      scope = Accounts.Scope.for_user(admin)

      for n <- 1..27 do
        {:ok, request} =
          Newsletters.request_signup("list-#{locale}-#{n}@example.org", %{
            consent: true,
            city: if(n == 1, do: "Montréal", else: "Laval"),
            fsa: "H2X"
          })

        {:ok, _} = Newsletters.confirm(request.confirmation_token)
      end

      {:ok, _} =
        Newsletters.request_signup("pending-list-#{locale}@example.org", %{
          consent: true,
          fsa: "H2X"
        })

      baseline = %{
        accounts: Repo.aggregate(Accounts.User, :count),
        people: Repo.aggregate(PhoenixCRM.Person, :count),
        consent: Repo.aggregate(Newsletters.ConsentEvent, :count),
        consent_ids: Enum.map(Repo.all(Newsletters.ConsentEvent), & &1.id),
        withdrawal_tokens: Repo.aggregate(Newsletters.WithdrawalToken, :count),
        subscriptions: Repo.all(Newsletters.Subscription)
      }

      {token, _} = generate_user_magic_link_token(admin)

      b =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> visit("/manage/mail/newsletters?locale=#{locale}")

      b =
        b
        |> fill_in(tr(locale, "List name"), with: "Montréal and H2X")
        |> fill_in(tr(locale, "Cities"), with: "Montréal")
        |> fill_in(tr(locale, "FSAs"), with: "H2X")
        |> click_button(tr(locale, "Save list"))

      {:ok, [list]} = Lists.list(scope)

      b =
        b
        |> visit("/manage/mail/newsletters?locale=#{locale}&list_id=#{list.id}")
        |> assert_has("#newsletter-audience", text: "list-#{locale}-1@example.org", exact: false)
        |> capture(
          locale,
          "Save OR rules and reload membership",
          "27 confirmed matches and one pending match; no consent granted"
        )

      {:ok, page} = Newsletters.audience_page(scope, %{"list_id" => list.id})
      assert page.counts.included == 27
      assert page.counts.unconfirmed == 1

      b =
        b
        |> click("#mailing-list-#{list.id} button[phx-click=list-compose]")
        |> fill_in(tr(locale, "Subject"), with: "Dynamic local newsletter #{locale}")
        |> fill_in(tr(locale, "Message · Markdown"), with: "Local synthetic newsletter")
        |> select(tr(locale, "Audience source"),
          option: tr(locale, "Mailing list · all eligible members"),
          exact: false
        )
        |> select("#draft_mailing_list_id", tr(locale, "Mailing list"),
          option: list.name,
          exact: false
        )
        |> click_button(tr(locale, "Save"))
        |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)

      {:ok, [draft]} = Drafts.list(scope)
      path = "/manage/mail/drafts/#{draft.id}?locale=#{locale}"

      b =
        b
        |> visit(path)
        |> assert_has("#whole-list-audience", text: "27")
        |> refute_has("button[phx-click=select-visible]")
        |> capture(
          locale,
          "Choose a named list and reload the draft",
          "Whole-list choice persists; no individual recipient selection"
        )

      b =
        b
        |> click_button(tr(locale, "Prepare batch"))
        |> assert_has("#newsletter-batch-review")
        |> capture(
          locale,
          "Prepare the whole list",
          "Exact snapshot contains all27 eligible members beyond the first25; no delivery"
        )

      {:ok, [batch]} = Batches.list(scope, draft.id)
      assert length(batch.recipient_keys) == 27
      assert Repo.aggregate(Delivery, :count) == 27

      b =
        b
        |> visit("/manage/mail/newsletters?locale=#{locale}")
        |> click("#mailing-list-#{list.id} button[phx-click=list-edit]")
        |> select("#list_match", tr(locale, "Combine rules"),
          option: tr(locale, "Match every rule (AND)"),
          exact: false
        )
        |> click_button(tr(locale, "Save list"))
        |> visit(path)
        |> click("button[phx-click=review-batch][phx-value-id='#{batch.id}']")
        |> click_button(tr(locale, "Approve batch"))
        |> assert_has("#newsletter-draft-error")
        |> capture(
          locale,
          "Change rules and attempt to approve the old snapshot",
          "Changed membership requires a new review; no message or consent change"
        )

      assert {:ok, %{counts: %{included: 1}}} =
               Newsletters.audience_page(scope, %{"list_id" => list.id})

      assert Repo.get!(Newsletters.Batch, batch.id).state == "review"
      assert Enum.all?(Repo.all(Delivery), &(&1.state == "pending"))
      assert Repo.aggregate(Accounts.User, :count) == baseline.accounts
      assert Repo.aggregate(PhoenixCRM.Person, :count) == baseline.people
      assert Repo.aggregate(Newsletters.ConsentEvent, :count) == baseline.consent + 27

      new_events =
        Enum.reject(Repo.all(Newsletters.ConsentEvent), &(&1.id in baseline.consent_ids))

      assert length(new_events) == 27

      assert Enum.all?(
               new_events,
               &(&1.kind == "withdrawal_link_created" and &1.actor_id == admin.id and
                   &1.subscription_id in batch.recipient_keys)
             )

      assert Repo.aggregate(Newsletters.WithdrawalToken, :count) ==
               baseline.withdrawal_tokens + 27

      assert Repo.all(Newsletters.Subscription) |> Enum.sort_by(& &1.id) ==
               Enum.sort_by(baseline.subscriptions, & &1.id)

      {:ok, %{revision: 2}} = Lists.get(scope, list.id)
      b
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, locale, trigger, outcome) do
      step = Process.get({:list_step, locale}, 0) + 1
      Process.put({:list_step, locale}, step)
      filename = "LIST-NEWS-01-#{locale}-#{step}.png"
      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(filename, trigger, outcome, %{
        "scenario_id" => "LIST-NEWS-01-#{locale}",
        "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(browser)),
        "step" => step,
        "external_systems" => "Synthetic local database only; no provider request or send"
      })

      browser
    end
  end
end
