if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.GroupsParticipationTest do
    use AcceptanceHarness.Playwright.Case, async: false
    alias PauseAiCa.{Accounts, Incubators, Newsletters, Participation, Repo, Volunteers}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "GROUP-PART-01-#{locale}",
                    title: "Local waitlist and incubator help · #{language}",
                    tags: ["participation", "incubators"],
                    roles: ["Interested visitor"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)
    setup_all do
      AtddEvidence.reset!("GROUP-PART-01 · one shared local participation form", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      previous = Application.get_env(:swoosh, :shared_test_process)
      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.put_env(:swoosh, :shared_test_process, previous) end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "GROUP-PART-01 waitlist and help #{locale}", c do
        locale = unquote(locale)
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        baseline = counts()
        path = if locale == "fr", do: "/fr/groupes", else: "/en/groups"

        b =
          c.conn
          |> visit("/#{locale}")
          |> PhoenixTest.Playwright.click("#involvement-menu summary")
          |> capture(locale, "Get involved menu", "Click Local groups")
          |> click_link("#act-local-groups", tr(locale, "Local groups"), exact: true)
          |> assert_has("[data-phx-main].phx-connected")
          |> assert_has("#participation-form")
          |> assert_has("#participation-fsa-help",
            text: tr(locale, "First three characters of your postal code, e.g. H2X.")
          )
          |> capture(
            locale,
            "Local groups shared form",
            "Enter details once; choose a waitlist or offer to help start an incubator"
          )

        for {kind, city} <- [{"waitlist", "Toronto"}, {"help", "Montréal"}], reduce: b do
          b ->
            email = "local-#{kind}-#{locale}@example.org"

            b =
              if kind == "help",
                do:
                  b
                  |> visit(path)
                  |> assert_has("[data-phx-main].phx-connected")
                  |> click_button(tr(locale, "Help start an incubator")),
                else: b

            b =
              b
              |> fill_in(tr(locale, "Name"), with: "Morgan Synthetic")
              |> fill_in(tr(locale, "Your email"), with: email)
              |> fill_in(tr(locale, "FSA"), with: "H2X")
              |> fill_in(tr(locale, "Where would you like to get involved?"), with: city)

            b =
              if kind == "help",
                do:
                  fill_in(b, tr(locale, "How would you like to help?"),
                    with: "I can help find a venue."
                  ),
                else: b

            b =
              b
              |> capture(
                locale,
                "#{kind}: details and explicit choices",
                "Only local contact is selected; account and newsletter choices remain available"
              )
              |> click("#participation-submit")
              |> assert_has("#account-email-pending")

            request = Repo.get_by!(Participation.Request, email: email)
            assert request.state == "pending" and request.local_kind == kind
            assert request.account == false and request.newsletter == false
            assert counts() == baseline
            assert_receive {:email, mail}, 8_000
            assert mail.to == [{"", email}] and mail.cc == [] and mail.bcc == []

            [_, url] =
              Regex.run(~r{href="(https?://[^\"]+/participation/confirm[^\"]+)"}, mail.html_body)

            b =
              b
              |> visit(String.replace(url, "&amp;", "&"))
              |> assert_has("#participation-confirm")

            assert Repo.get!(Participation.Request, request.id).state == "pending"

            b =
              b
              |> click("#participation-confirm")
              |> assert_has("#participation-result")
              |> capture(
                locale,
                "#{kind}: confirmed local request",
                "Email confirmation records this purpose only"
              )

            assert Repo.get!(Participation.Request, request.id).state == "confirmed"
            assert counts() == baseline
            b
        end

        AtddEvidence.mark_scenario_success!(
          Enum.find(@scenarios, &(&1.id == "GROUP-PART-01-#{locale}"))
        )
      end
    end

    defp counts,
      do: %{
        accounts: Repo.aggregate(Accounts.User, :count),
        subscriptions: Repo.aggregate(Newsletters.Subscription, :count),
        memberships: Repo.aggregate(Incubators.Membership, :count),
        managers: Repo.aggregate(Volunteers.Manager, :count),
        deliveries: Repo.aggregate(Newsletters.Delivery, :count)
      }

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(b, locale, control, outcome) do
      PhoenixTest.Playwright.evaluate(
        b,
        "document.documentElement.scrollWidth <= window.innerWidth",
        &assert(&1)
      )

      sid = "GROUP-PART-01-#{locale}"
      step = Process.get({:group_part_step, sid}, 0) + 1
      Process.put({:group_part_step, sid}, step)
      name = "#{sid}-#{step}.png"
      PhoenixTest.Playwright.evaluate(b, "location.href", &Process.put(:group_part_url, &1))

      metadata = %{
        "scenario_id" => sid,
        "url" => AtddEvidence.safe_url(Process.get(:group_part_url)),
        "control" => control,
        "source" =>
          "Actual local shared participation form; synthetic accounts and Swoosh confirmation only"
      }

      AcceptanceHarness.Evidence.record_pending_step(name, control, outcome, metadata)
      b = AtddEvidence.capture_full_page(b, name)

      AtddEvidence.record_step(
        name,
        control,
        outcome,
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(b)))
      )

      b
    end
  end
end
