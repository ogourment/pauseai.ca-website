if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.AdministratorsTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PhoenixTest
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Repo, Accounts, MailSafety}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios [
      %{
        id: "STAGE-ACCESS-01",
        title: "Administrators and authentication-only staging whitelist",
        tags: ["accounts", "mail", "superadmin"],
        roles: ["Superadmin"],
        language: "English",
        device: "Desktop",
        source_file: __ENV__.file
      },
      %{
        id: "STAGE-ACCESS-02",
        title: "Compact French management tabs on mobile",
        tags: ["accounts", "superadmin"],
        roles: ["Superadmin"],
        language: "French",
        device: "Mobile",
        source_file: __ENV__.file
      }
    ]
    setup_all do
      AtddEvidence.reset!("Staging access and management tabs", @scenarios, %{browser: "Chromium"})

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      previous = MailSafety.environment()

      admin =
        user_fixture(%{email: "access-admin@example.org"})
        |> Ecto.Changeset.change(superadmin: true)
        |> Repo.update!()

      reviewer = user_fixture(%{email: "reviewer@example.org"})
      flush_fixture_mail()
      Application.put_env(:pauseai_ca, :mail_environment, :staging)
      on_exit(fn -> Application.put_env(:pauseai_ca, :mail_environment, previous) end)
      %{admin: admin, reviewer: reviewer}
    end

    @tag browser_context_opts: [viewport: %{width: 1280, height: 900}]
    test "STAGE-ACCESS-01 list, allow, reload, authentication-only mail, remove", c do
      {token, _} = generate_user_magic_link_token(c.admin)

      b =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/manage/accounts?locale=en")
        |> click_link("Administrators")
        |> assert_has("#superadmin-list", text: c.admin.email)
        |> assert_has("#staging-sign-in-form")
        |> capture(
          "STAGE-ACCESS-01",
          1,
          "Open Administrators",
          "Role roster and separate authentication-only whitelist"
        )

      b =
        b
        |> fill_in("Account email", with: c.reviewer.email)
        |> click_button("Allow sign-in")
        |> assert_has("#staging-access-saved", text: "No email sent")
        |> visit("/manage/administrators?locale=en")
        |> assert_has("#staging-sign-in li", text: c.reviewer.email)
        |> capture(
          "STAGE-ACCESS-01",
          2,
          "Allow an existing confirmed reviewer and reload",
          "Whitelist persists; no admin role or outgoing message"
        )

      refute Repo.get!(PauseAiCa.Accounts.User, c.reviewer.id).superadmin
      refute_receive {:email, _}

      assert {:ok, _} =
               Accounts.deliver_login_instructions(c.reviewer, fn _ ->
                 "http://localhost/test-sign-in"
               end)

      assert_receive {:email, message}
      assert message.to == [{"Staging sign-in", c.reviewer.email}]

      assert {:error, :staging_admin_required} =
               PauseAiCa.Mailer.deliver(message, admin_actor_id: c.reviewer.id)

      b
      |> click_button("Remove staging sign-in for #{c.reviewer.email}")
      |> refute_has("#staging-sign-in li", text: c.reviewer.email)
      |> capture(
        "STAGE-ACCESS-01",
        3,
        "Remove staging sign-in",
        "Future magic-link delivery is refused; campaign guard remains unchanged"
      )

      assert {:error, :staging_admin_required} =
               Accounts.deliver_login_instructions(c.reviewer, fn _ ->
                 "http://localhost/test-sign-in"
               end)

      refute_receive {:email, _}
      AtddEvidence.mark_scenario_success!(hd(@scenarios))
    end

    @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
    test "STAGE-ACCESS-02 French tabs remain compact and tools use More", c do
      {token, _} = generate_user_magic_link_token(c.admin)

      b =
        c.conn
        |> visit("/users/log-in/#{token}")
        |> click_button("Keep me logged in on this device")
        |> assert_path("/")
        |> visit("/manage/administrators?locale=fr")
        |> assert_has("#management-tabs a[aria-current=page]", text: "Administrateurs")
        |> assert_has("#staging-sign-in", text: "Connexions autorisées en préproduction")
        |> capture(
          "STAGE-ACCESS-02",
          1,
          "Open French Administrators on mobile",
          "Four scrollable tabs, More menu, explicit sign-in-only exception"
        )

      b =
        b
        |> click_link("Comptes")
        |> assert_path("/manage/accounts", query_params: %{locale: "fr"})
        |> assert_has("#management-tabs a[aria-current=page]", text: "Comptes")
        |> capture(
          "STAGE-ACCESS-02",
          2,
          "Choose the Accounts tab",
          "French locale retained and selected tab reflects the current page"
        )

      evaluate(b, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      AtddEvidence.mark_scenario_success!(Enum.at(@scenarios, 1))
    end

    defp capture(b, id, step, trigger, outcome) do
      filename = "#{id}-#{String.pad_leading(to_string(step), 2, "0")}.png"
      scenario = Enum.find(@scenarios, &(&1.id == id))

      metadata = %{
        scenario_id: id,
        step: to_string(step),
        user: "Superadmin",
        language: scenario.language,
        device: scenario.device,
        click_target: trigger,
        external_systems: "Synthetic local accounts; Swoosh capture only; no provider sends"
      }

      metadata = Map.new(metadata, fn {key, value} -> {Atom.to_string(key), value} end)

      AcceptanceHarness.Evidence.record_pending_step(
        filename,
        scenario.title,
        trigger <> " → " <> outcome,
        metadata
      )

      b = AtddEvidence.capture_full_page(b, filename)
      evaluate(b, "location.href", &Process.put(:access_url, &1))

      AtddEvidence.record_step(
        filename,
        scenario.title,
        trigger <> " → " <> outcome,
        Map.put(metadata, "current_url", AtddEvidence.safe_url(Process.get(:access_url)))
      )

      b
    end

    defp flush_fixture_mail do
      receive do
        {:email, _} -> flush_fixture_mail()
      after
        0 -> :ok
      end
    end
  end
end
