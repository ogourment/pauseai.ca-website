if System.get_env("ATDD") == "true" do
  defmodule PauseAiCaWeb.Atdd.NovemberMarchesTest do
    use AcceptanceHarness.Playwright.Case, async: false
    import PauseAiCa.AccountsFixtures
    alias PauseAiCaWeb.AtddEvidence
    @moduletag :atdd

    for {locale, width} <- [{"en", 1280}, {"fr", 390}, {"en", 390}, {"fr", 1280}] do
      @tag browser_context_opts: [viewport: %{width: width, height: 900}]
      test "Nov14 public banner links, header geometry and contrast #{locale} #{width}", c do
        locale = unquote(locale)
        width = unquote(width)
        Ecto.Adapters.SQL.Sandbox.mode(PauseAiCa.Repo, {:shared, self()})
        browser = c.conn |> visit("/#{locale}") |> assert_has("#site-header")
        before? = System.get_env("SLATE_MARCHES_BEFORE") == "1"

        expired? = DateTime.compare(DateTime.utc_now(), ~U[2026-11-15 05:00:00Z]) != :lt

        if before? or expired? do
          refute_has(browser, "#november-marches-banner")
        else
          verify(browser, locale)
        end

        capture(browser, locale, width, "guest")

        user =
          user_fixture() |> Ecto.Changeset.change(superadmin: true) |> PauseAiCa.Repo.update!()

        {token, _} = generate_user_magic_link_token(user)

        browser =
          browser
          |> visit("/users/log-in/#{token}?locale=en")
          |> click_button("Keep me logged in on this device")
          |> assert_path("/")
          |> visit("/#{locale}")
          |> assert_has("#site-header")

        unless before? or expired?, do: verify(browser, locale)
        capture(browser, locale, width, "signed-in")

        browser
        |> visit("/manage/mail/newsletters?locale=#{locale}")
        |> assert_has("[data-phx-main].phx-connected #newsletters")
        |> refute_has("#november-marches-banner")
      end
    end

    defp verify(browser, locale) do
      label = if locale == "fr", do: "Marches du 14 novembre :", else: "November 14 marches:"
      assert_has(browser, "#november-marches-banner time[datetime='2026-11-14']", text: label)

      browser
      |> assert_has("#march-montreal[href='https://luma.com/g93q6ksk?tk=EYSylQ']")
      |> assert_has("#march-toronto[href='https://luma.com/20vit6m2']")

      {:ok, geometry} =
        PlaywrightEx.Frame.evaluate(browser.frame_id,
          expression:
            "(async()=>{await document.fonts.ready; await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))); const b=document.querySelector('#november-marches-banner').getBoundingClientRect(), h=document.querySelector('#site-header').getBoundingClientRect(); return {top:b.top,headerTop:h.top,height:b.height,overflow:document.documentElement.scrollWidth>innerWidth,offset:parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--header-height')),headerHeight:h.height}})()",
          timeout: 8000
        )

      assert geometry["top"] == geometry["headerTop"]
      assert geometry["height"] > 0
      refute geometry["overflow"]
      assert abs(geometry["offset"] - geometry["headerHeight"]) <= 1

      {:ok, sizes} =
        PlaywrightEx.Frame.evaluate(browser.frame_id,
          expression:
            "[...document.querySelectorAll('#november-marches-banner a')].map(e=>({width:e.getBoundingClientRect().width,height:e.getBoundingClientRect().height}))",
          timeout: 8000
        )

      assert Enum.all?(sizes, &(&1["width"] >= 24 and &1["height"] >= 24))

      for theme <- ["light", "dark"] do
        {:ok, _} =
          PlaywrightEx.Frame.evaluate(browser.frame_id,
            expression: "document.documentElement.dataset.theme='#{theme}'",
            timeout: 8000
          )

        {:ok, _} =
          PlaywrightEx.Frame.hover(browser.frame_id,
            selector: "#november-marches-banner span",
            timeout: 8000
          )

        ratio =
          min(
            contrast(browser, "#march-montreal", false),
            contrast(browser, "#march-toronto", false)
          )

        assert ratio >= 4.5

        {:ok, _} =
          PlaywrightEx.Frame.hover(browser.frame_id, selector: "#march-montreal", timeout: 8000)

        hover_ratio = contrast(browser, "#march-montreal", false)
        assert hover_ratio >= 4.5
        browser = press(browser, "#march-montreal", "Tab")

        {:ok, focused} =
          PlaywrightEx.Frame.evaluate(browser.frame_id,
            expression: "document.querySelector('#march-toronto').matches(':focus-visible')",
            timeout: 8000
          )

        assert focused
        focus_ratio = contrast(browser, "#march-toronto", true)
        assert focus_ratio >= 3

        IO.puts(
          "March banner contrast #{theme}: normal #{Float.round(ratio, 2)}:1; hover #{Float.round(hover_ratio, 2)}:1; focus #{Float.round(focus_ratio, 2)}:1"
        )
      end

      {:ok, _} =
        PlaywrightEx.Frame.evaluate(browser.frame_id,
          expression:
            "document.documentElement.dataset.theme='light';document.activeElement.blur();window.scrollTo(0,0)",
          timeout: 8000
        )

      {:ok, _} =
        PlaywrightEx.Frame.hover(browser.frame_id,
          selector: "#november-marches-banner span",
          timeout: 8000
        )

      browser
    end

    defp contrast(browser, selector, outline?) do
      {:ok, ratio} =
        PlaywrightEx.Frame.evaluate(browser.frame_id,
          expression:
            "(()=>{const e=document.querySelector('#{selector}'),s=getComputedStyle(e),bg=getComputedStyle(document.querySelector('#november-marches-banner')).backgroundColor; const rgb=c=>{const x=document.createElement('canvas').getContext('2d');x.fillStyle=c;x.fillRect(0,0,1,1);const p=x.getImageData(0,0,1,1).data;if(p[3]!==255)throw Error('nonopaque contrast sample');return [...p].slice(0,3).map(v=>v/255)}; const lum=c=>rgb(c).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((a,v,i)=>a+v*[.2126,.7152,.0722][i],0);let a=lum(#{if outline?, do: "s.outlineColor", else: "s.color"}),b=lum(bg);return (Math.max(a,b)+.05)/(Math.min(a,b)+.05)})()",
          timeout: 8000
        )

      ratio
    end

    defp capture(browser, locale, width, kind) do
      if System.get_env("SLATE_MARCHES_CAPTURE") do
        phase = if System.get_env("SLATE_MARCHES_BEFORE") == "1", do: "before", else: "after"
        filename = "marches-#{locale}-#{width}-#{kind}-#{phase}.png"

        IO.puts(
          "Capture URL: http://127.0.0.1:4186/#{locale}; preceding action: #{kind} visitor opens homepage"
        )

        AtddEvidence.capture_full_page(browser, filename)
        File.mkdir_p!("tmp/slate-marches")

        for suffix <- ["", ".html"],
            do:
              File.cp!(
                "tmp/atdd/screenshots/" <> filename <> suffix,
                "tmp/slate-marches/" <> filename <> suffix
              )
      end

      browser
    end
  end
end
