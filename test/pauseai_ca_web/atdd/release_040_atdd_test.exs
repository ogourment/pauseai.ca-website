if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.Release040Test do
    use AcceptanceHarness.Playwright.Case, async: false
    import PhoenixTest
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Repo}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios Enum.map(
                 [
                   {"DOM-01", "French domain follows account creation through delivered email"},
                   {"VISIT-01", "Marked browser visits stay excluded after sign-out"},
                   {"VOL-11", "Hidden volunteer profile preserves the usable account profile"}
                 ],
                 fn {id, title} ->
                   %{
                     id: id,
                     title: title,
                     language: "English / French",
                     device: "Desktop",
                     roles: ["Visitor / member / superadmin"],
                     source_file: __ENV__.file
                   }
                 end
               )

    setup_all do
      AtddEvidence.reset!("0.4.0 acceptance evidence", @scenarios, %{
        browser: "Chromium",
        viewport: "1280×900"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      mailbox = Application.get_env(:swoosh, :shared_test_process)
      origins = Application.get_env(:pauseai_ca, :public_origins)
      visits = Application.get_env(:pauseai_ca, :record_visits)
      Application.put_env(:swoosh, :shared_test_process, self())
      port = System.get_env("ATDD_PORT", "4116")
      en = "http://127.0.0.1:#{port}"
      fr = "http://fr.localhost:#{port}"
      Application.put_env(:pauseai_ca, :public_origins, %{"en" => en, "fr" => fr})

      on_exit(fn ->
        Application.put_env(:swoosh, :shared_test_process, mailbox)
        Application.put_env(:pauseai_ca, :public_origins, origins)
        Application.put_env(:pauseai_ca, :record_visits, visits)
      end)

      %{en: en, fr: fr}
    end

    test "DOM-01 French arrival, delivered email, confirmation and explicit English", c do
      id = "DOM-01"

      b =
        c.conn
        |> visit(c.fr <> "/?source=domain-review")
        |> assert_path("/fr", query_params: %{source: "domain-review"})

      b =
        b
        |> assert_has("html[lang=fr]")
        |> capture(id, "Arrive on the French domain", "French home retains the campaign query")

      b =
        b
        |> visit(c.fr <> "/users/register")
        |> assert_has("[data-phx-main].phx-connected")
        |> fill_in("Courriel", with: "domain-acceptance@example.org")
        |> click_button("Recevoir un lien de connexion")
        |> assert_has("#account-email-pending")

      b =
        capture(
          b,
          id,
          "Create an account",
          "French form acknowledges the real local email delivery"
        )

      assert_receive {:email, email}, 8_000
      assert email.to == [{"", "domain-acceptance@example.org"}]
      assert email.cc == [] and email.bcc == []
      [_, url] = Regex.run(~r{href="(https?://[^"]+/users/log-in/[^"]+)"}, email.html_body)
      url = String.replace(url, "&amp;", "&")
      assert String.starts_with?(url, c.fr <> "/users/log-in/")
      [_, body] = Regex.run(~r{<body[^>]*>(.*)</body>}s, email.html_body)

      b =
        b
        |> visit(
          "data:text/html;base64," <>
            Base.encode64(
              "<html><meta charset='utf-8'><body><h1>Captured test email · No external delivery</h1>#{body}</body></html>"
            )
        )
        |> capture(
          id,
          "Read the delivered sign-in email",
          "The ownership link uses the configured French origin"
        )

      b =
        b
        |> click_link("Confirm account · Confirmer le compte")
        |> assert_has("html[lang=fr]")
        |> click_button("Confirmer et rester connecté")
        |> assert_has("#account-menu")
        |> assert_has("html[lang=fr]")

      evaluate(b, "location.origin", &assert(&1 == c.fr))
      assert Accounts.get_user_by_email("domain-acceptance@example.org").confirmed_at

      b
      |> capture(id, "Confirm ownership", "Signed-in French account on the French domain")
      |> visit(c.fr <> "/en")
      |> assert_has("html[lang=en]")
      |> capture(
        id,
        "Choose English explicitly",
        "Explicit language choice remains available on the French host"
      )

      finish(id)
    end

    test "VOL-11 both languages redirect saved links and preserve editable account data", c do
      id = "VOL-11"
      user = user_fixture(%{email: "profile-hidden@example.org"})

      profile =
        Repo.insert!(%PauseAiCa.Volunteers.Profile{
          user_id: user.id,
          details: %{"city" => "Montréal", "contact_notes" => "Synthetic preserved detail"}
        })

      b = sign_in(c.conn, user)

      for {locale, path, name, postal, city, save} <- [
            {"en", "/en/profile", "Name", "Full postal code", "City", "Find my MP"},
            {"fr", "/fr/profil", "Nom", "Code postal complet", "Ville", "Trouver mon député·e"}
          ] do
        b =
          b
          |> visit("/volunteer-profile?locale=" <> locale)
          |> assert_path(path)
          |> assert_has("[data-phx-main].phx-connected")
          |> refute_has("a[href*='volunteer-profile']")

        b =
          b
          |> fill_in(name, with: "Profile Review")
          |> fill_in(postal, with: "H2X 1Y4")
          |> fill_in(city, with: "Montréal")
          |> click_button(save)
          |> assert_has("#flash-info",
            text: if(locale == "fr", do: "Profil enregistré.", else: "Profile saved.")
          )

        assert Accounts.get_user!(user.id).name == "Profile Review"
        assert Repo.get!(PauseAiCa.Volunteers.Profile, profile.id).details == profile.details

        b
        |> visit(path)
        |> assert_has("#profile-form input[value='Profile Review']")
        |> capture(
          id,
          "Open saved #{locale} link and save the normal profile",
          "Localized profile remains usable; stored volunteer details are preserved"
        )
      end

      finish(id)
    end

    test "VISIT-01 exclusion, sign-out, independent browser, revocation and authorization", c do
      id = "VISIT-01"
      Application.put_env(:pauseai_ca, :record_visits, true)

      admin =
        user_fixture(%{email: "visits-admin@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      b =
        c.conn
        |> observe_visits()
        |> sign_in(admin)
        |> visit("/admin/dashboard")
        |> assert_has("#visit-preferences")

      baseline = visits()

      b =
        b
        |> click_button("Exclude this browser")
        |> assert_has("#browser-visit-exclusion-status", text: "also excluded")
        |> capture(
          id,
          "Exclude this browser",
          "Dashboard confirms signed-out visits are excluded"
        )

      b = b |> log_out() |> visit("/en") |> wait_visit()
      assert visits() == baseline

      b =
        capture(
          b,
          id,
          "Sign out and visit a public page",
          "Actual browser signal leaves the database total unchanged"
        )

      other = new_device(c) |> observe_visits() |> visit("/en") |> wait_visit()
      assert visits() == baseline + 1

      capture(
        other,
        id,
        "Visit from an independent browser",
        "An unmarked browser adds one daily visit"
      )

      b =
        b
        |> sign_in(admin)
        |> visit("/admin/dashboard")
        |> click_button("Include this browser")
        |> assert_has("#browser-visit-exclusion-status", text: "can count")
        |> log_out()
        |> visit("/en")
        |> wait_visit()

      assert visits() == baseline + 2
      capture(b, id, "Re-enable and sign out", "The formerly excluded browser counts again")
      member = user_fixture(%{email: "visits-member@example.org"})
      ordinary = new_device(c) |> sign_in(member) |> visit("/en/profile")

      evaluate(
        ordinary,
        "(async () => { const response = await fetch('/admin/visit-preferences', {method:'POST', headers:{'content-type':'application/x-www-form-urlencoded','x-csrf-token':document.querySelector('meta[name=csrf-token]').content},body:'excluded=true'}); return response.status })()",
        &assert(&1 == 403)
      )

      {:ok, cookies} = PlaywrightEx.BrowserContext.cookies(ordinary.context_id, timeout: 5_000)
      refute Enum.any?(cookies, &(&1.name == "_pauseai_exclude_visits"))

      capture(
        ordinary,
        id,
        "Attempt the reserved action as a normal member",
        "Server rejects the preference change with 403"
      )

      finish(id)
    end

    defp sign_in(b, user) do
      {token, _} = generate_user_magic_link_token(user)

      b
      |> visit("/users/log-in/#{token}?locale=en")
      |> click_button("Keep me logged in on this device")
      |> assert_has("#account-menu")
    end

    defp log_out(b),
      do:
        b
        |> click("#account-menu summary")
        |> click_link("Log out")
        |> refute_has("#account-menu")

    defp new_device(c),
      do:
        PhoenixTest.Playwright.Case.new_session(
          PhoenixTest.Playwright.Config.validate!(
            browser_context_opts: [viewport: %{width: 1280, height: 900}]
          ),
          c
        )

    defp visits do
      case Repo.aggregate(PauseAiCa.Engagement.DailyVisit, :sum, :count) do
        nil -> 0
        %Decimal{} = n -> Decimal.to_integer(n)
        n -> n
      end
    end

    defp observe_visits(b) do
      {:ok, _} =
        PlaywrightEx.BrowserContext.add_init_script(b.context_id,
          source: """
          const originalFetch = window.fetch;
          window.fetch = (...args) => {
            const pending = originalFetch(...args);
            if (String(args[0]).includes('/engagement/visits')) pending.then(r => {
              if (r.ok) document.documentElement.dataset.visitSignalComplete = 'true';
            });
            return pending;
          };
          """,
          timeout: 5_000
        )

      b
    end

    defp wait_visit(b), do: assert_has(b, "html[data-visit-signal-complete=true]")

    defp capture(b, id, trigger, outcome) do
      scenario = Enum.find(@scenarios, &(&1.id == id))
      step = Process.get({:step, id}, 0) + 1
      Process.put({:step, id}, step)
      filename = "#{id}-#{step}.png"
      started = System.monotonic_time(:millisecond)
      b = AtddEvidence.capture_full_page(b, filename)
      evaluate(b, "location.href", &Process.put(:url, &1))

      AtddEvidence.record_step(filename, scenario.title, trigger <> " → " <> outcome, %{
        "duration_ms" => System.monotonic_time(:millisecond) - started,
        "scenario_id" => id,
        "step" => to_string(step),
        "user" => "Synthetic visitor / account",
        "current_url" => AtddEvidence.safe_url(Process.get(:url)),
        "language" => "English / French",
        "device" => "Desktop 1280px",
        "geometry" => Process.get(:evidence_geometry),
        "external_systems" => "Local database and isolated Swoosh mail only"
      })

      b
    end

    defp finish(id) do
      scenario = Enum.find(@scenarios, &(&1.id == id))
      AtddEvidence.mark_scenario_success!(scenario)
      AcceptanceHarness.Evidence.record_current_scenario_runtime(scenario)
    end
  end
end
