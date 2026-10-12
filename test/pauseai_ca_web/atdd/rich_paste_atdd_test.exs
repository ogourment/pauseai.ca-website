if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.RichPasteTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCa.{Accounts, Newsletters, Repo}
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd
    @scenarios (for {locale, language, device} <- [
                      {"en", "English", "Desktop"},
                      {"fr", "French", "Phone"}
                    ] do
                  %{
                    id: "PA-NEWS-PASTE-01-#{locale}",
                    title: "Rich newsletter paste stays editable and durable · #{language}",
                    tags: ["newsletter", "mail", "superadmin"],
                    roles: ["Superadmin"],
                    language: language,
                    device: device,
                    source_file: __ENV__.file
                  }
                end)

    setup_all do
      AtddEvidence.reset!("PA-NEWS-PASTE-01 · rich clipboard to Markdown", @scenarios, %{
        browser: "Chromium",
        viewport: "Desktop and phone"
      })

      on_exit(fn -> AtddEvidence.finalize!() end)
      :ok
    end

    for {locale, width, height} <- [{"en", 1280, 900}, {"fr", 390, 844}] do
      @tag screenshot: true
      @tag browser_context_opts: [viewport: %{width: width, height: height}]
      test "PA-NEWS-PASTE-01 rich clipboard journey #{locale}", c do
        locale = unquote(locale)
        Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
        admin = user_fixture() |> Ecto.Changeset.change(superadmin: true) |> Repo.update!()
        scope = Accounts.Scope.for_user(admin)
        {:ok, draft} = Newsletters.Drafts.create(scope)
        path = "/manage/mail/drafts/#{draft.id}?locale=#{locale}"
        b = c.conn |> sign_in(admin) |> visit(path) |> assert_has("[data-phx-main].phx-connected")

        b =
          b
          |> fill_in(tr(locale, "Subject"), with: "Synthetic rich paste")
          |> fill_in(tr(locale, "Message · Markdown"), with: "Before REPLACE after")

        b =
          PhoenixTest.Playwright.evaluate(b, """
          (()=>{const el=document.querySelector('[data-pme-source]');el.focus();el.setSelectionRange(7,14);const data=new DataTransfer();data.setData('text/plain','plain fallback');data.setData('text/html','<b style="font-weight:normal"><h2>Local news</h2><p><span style="font-weight:700">Bold</span> and <span style="font-style:italic">italique</span> <a href="https://www.google.com/url?q=https://example.org/news">News</a></p><ul><li>First</li><li>Second<ul><li>Nested</li></ul></li></ul></b><p><a href="javascript:alert(1)">Safe text</a></p><script>window.clipboardExecuted=true</script>');el.dispatchEvent(new ClipboardEvent('paste',{bubbles:true,cancelable:true,clipboardData:data}));})()
          """)

        b =
          b
          |> assert_has("#newsletter-save-status", text: tr(locale, "Unsaved changes"))
          |> click_button(tr(locale, "Save"))
          |> assert_has("#newsletter-save-status", text: tr(locale, "Saved"), exact: true)

        {:ok, saved} = Newsletters.Drafts.get(scope, draft.id)
        assert saved.source =~ "Before ## Local news"
        assert saved.source =~ "**Bold** and *italique*"
        assert saved.source =~ "[News](https://example.org/news)"
        assert saved.source =~ ~r/-\s+First/
        assert saved.source =~ ~r/-\s+Nested/
        assert String.ends_with?(saved.source, "Safe text after")
        refute saved.source =~ "javascript:"
        refute saved.source =~ "clipboardExecuted"
        b = b |> visit(path) |> assert_has("[data-pme-source]", text: saved.source)

        b =
          PhoenixTest.Playwright.evaluate(
            b,
            """
            (()=>{const el=document.querySelector('[data-pme-source]');const data=new DataTransfer();data.setData('text/plain','**already Markdown**');const event=new ClipboardEvent('paste',{bubbles:true,cancelable:true,clipboardData:data});el.dispatchEvent(event);return {prevented:event.defaultPrevented,executed:!!window.clipboardExecuted};})()
            """,
            fn result -> assert result == %{"prevented" => false, "executed" => false} end
          )

        filename = "PA-NEWS-PASTE-01-#{locale}-1.png"
        b = AtddEvidence.capture_full_page(b, filename)

        AtddEvidence.record_step(
          filename,
          "Paste rich content, save and reload",
          "Headings, styles, links and nested lists become durable Markdown; plain text retains native paste; no provider call or delivery",
          %{
            "scenario_id" => "PA-NEWS-PASTE-01-#{locale}",
            "page_html" => AtddEvidence.scrub_html(AtddEvidence.page_html(b)),
            "step" => 1,
            "external_systems" => "Synthetic clipboard and database only"
          }
        )

        assert Repo.aggregate(Newsletters.Delivery, :count) == 0
        assert Repo.aggregate(Newsletters.Batch, :count) == 0
      end
    end

    defp sign_in(browser, user) do
      {token, _} = generate_user_magic_link_token(user)

      browser
      |> visit("/users/log-in/#{token}")
      |> click_button("Keep me logged in on this device")
      |> assert_path("/")
    end

    defp tr(locale, text),
      do:
        Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
          Gettext.gettext(PauseAiCaWeb.Gettext, text)
        end)
  end
end
