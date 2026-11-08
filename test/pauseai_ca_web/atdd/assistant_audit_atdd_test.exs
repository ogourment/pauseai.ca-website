if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.AssistantAuditTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Assistant, AssistantFixtures, Repo}
    alias PauseAiCaWeb.AtddEvidence
    alias PhoenixAgentAssistant.Store
    @moduletag :atdd
    @scenarios (for locale <- ["en", "fr"] do
                  %{
                    id: "CRM-ASSIST-AUDIT-01-#{locale}",
                    title: "Protected metadata activity while assistant remains off",
                    roles: ["Superadmin", "Revoked administrator"],
                    language: locale,
                    device: if(locale == "fr", do: "Phone", else: "Desktop"),
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("Protected assistant activity", @scenarios, %{
        fixture: "Synthetic AssistantFixtures; no provider network"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    setup do
      Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
      previous = Application.fetch_env(:pauseai_ca, :agent_assistant)
      config = AssistantFixtures.configuration(self())
      Application.put_env(:pauseai_ca, :agent_assistant, config)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:pauseai_ca, :agent_assistant, value)
          :error -> Application.delete_env(:pauseai_ca, :agent_assistant)
        end
      end)

      admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()

      for index <- 1..32 do
        {:ok, _} =
          Store.record(
            Assistant.store(),
            admin.id,
            "audit-native-#{index}",
            %{"kind" => "mode_changed", "mode" => "fast", "text" => "PRIVATE-AUDIT-SENTINEL"},
            config[:audit_keys]
          )
      end

      %{admin: admin}
    end

    for {locale, width} <- [{"en", 1280}, {"fr", 390}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: 900}]
      test "CRM-ASSIST-AUDIT-01-#{locale} settings to filtered audit and fresh revocation", c do
        locale = unquote(locale)
        id = "CRM-ASSIST-AUDIT-01-#{locale}"
        refute Store.enabled?(Assistant.store())
        {token, _} = generate_user_magic_link_token(c.admin)

        browser =
          c.conn
          |> visit("/users/log-in/#{token}?locale=en")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/admin/assistant?locale=#{locale}")
          |> assert_has("[data-phx-main].phx-connected #assistant-activity-link")
          |> assert_has("#journey-breadcrumbs a[href='/admin/dashboard?locale=#{locale}']",
            text: "Admin",
            exact: true
          )
          |> assert_has("#assistant-status", text: tr(locale, "Off"), exact: true)
          |> visible_table_fields("#assistant-token-limits", 7)
          |> click_link("#assistant-activity-link", tr(locale, "Activity & security"))
          |> assert_has("[data-phx-main].phx-connected #assistant-audit")
          |> visible_table_fields("#assistant-audit-table", 5)
          |> assert_has("#journey-breadcrumbs a[href='/admin/dashboard?locale=#{locale}']",
            text: "Admin",
            exact: true
          )
          |> refute_has("#assistant-audit", text: "PRIVATE-AUDIT-SENTINEL")
          |> capture(
            id,
            "Protected activity",
            "/admin/assistant?locale=#{locale}",
            tr(locale, "Activity & security")
          )
          |> select("#audit-kind", tr(locale, "Activity"),
            option: tr(locale, "Mode changed"),
            exact: false
          )
          |> assert_has("#audit-kind", value: "mode_changed")
          |> assert_has("#assistant-audit-next")

        evaluate(
          browser,
          "document.querySelectorAll('#assistant-audit-table tbody tr').length",
          &assert(&1 == 25)
        )

        browser =
          browser
          |> click_button("#assistant-audit-next", tr(locale, "Older"))
          |> assert_has("#audit-kind", value: "mode_changed")
          |> refute_has("#assistant-audit-next")
          |> refute_has("#assistant-audit", text: "PRIVATE-AUDIT-SENTINEL")
          |> capture(
            id,
            "Older filtered activity",
            "Activity; Mode changed filter",
            tr(locale, "Older")
          )

        evaluate(
          browser,
          "document.querySelectorAll('#assistant-audit-table tbody tr').length",
          &assert(&1 == 7)
        )

        refute Store.enabled?(Assistant.store())
        c.admin |> Ecto.Changeset.change(superadmin: false) |> Repo.update!()

        browser =
          browser
          |> click_button("#assistant-audit-first", tr(locale, "Newest"))
          |> assert_path("/")

        refute_receive {:assistant_generated, _, _}
        AtddEvidence.mark_scenario_success!(Enum.find(@scenarios, &(&1.id == id)))
        browser
      end
    end

    defp visible_table_fields(browser, selector, count) do
      evaluate(
        browser,
        """
        (() => {
          const cells = [...document.querySelectorAll('#{selector} tbody tr:first-child td')];
          return cells.length === #{count} && cells.every(cell => {
            const box = cell.getBoundingClientRect();
            const label = cell.dataset.label;
            return label && box.width > 0 && box.left >= 0 && box.right <= innerWidth &&
              cell.scrollWidth <= cell.clientWidth + 1 &&
              (innerWidth > 700 || (getComputedStyle(cell, '::before').display === 'block' && !['none', '""'].includes(getComputedStyle(cell, '::before').content)));
          });
        })()
        """,
        &assert(&1)
      )

      browser
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)

    defp capture(browser, id, title, preceding, control) do
      evaluate(browser, "document.documentElement.scrollWidth <= innerWidth", &assert(&1))
      step = Process.get({:audit_step, id}, 0) + 1
      Process.put({:audit_step, id}, step)
      filename = "#{id}-#{step}.png"
      evaluate(browser, "location.href", &Process.put(:audit_capture_url, &1))

      metadata = %{
        "scenario_id" => id,
        "url" => AtddEvidence.safe_url(Process.get(:audit_capture_url)),
        "preceding_screen" => preceding,
        "control" => control,
        "fixture" => "Synthetic accounts and protected audit rows; no provider calls"
      }

      AcceptanceHarness.Evidence.record_pending_step(
        filename,
        title,
        "Only authenticated metadata is disclosed; assistant stays off.",
        metadata
      )

      browser = AtddEvidence.capture_full_page(browser, filename)

      AtddEvidence.record_step(
        filename,
        title,
        "Only authenticated metadata is disclosed; assistant stays off.",
        Map.put(metadata, "page_html", AtddEvidence.scrub_html(AtddEvidence.page_html(browser)))
      )

      browser
    end
  end
end
