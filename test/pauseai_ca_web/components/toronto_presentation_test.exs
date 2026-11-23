defmodule PauseAiCaWeb.TorontoPresentationTest do
  use ExUnit.Case, async: true
  alias PauseAiCaWeb.TorontoPresentation

  test "Toronto payment destinations use the existing national page in either locale" do
    for {locale, path} <- [{"en", "/en/donate"}, {"fr", "/fr/faire-un-don"}] do
      for destination <- [
            "https://donate.stripe.com/old-link",
            "https://buy.stripe.com/old-link",
            "https://manifund.org/projects/pauseai-toronto",
            "/groups/toronto/pages/donate?locale=en#monthly",
            "/donate.html#once",
            "https://pauseaitoronto.info/donate"
          ] do
        assert TorontoPresentation.national_donations(
                 ~s(<a href="#{destination}">Give</a>),
                 locale
               ) ==
                 ~s(<a href="#{path}">Give</a>)
      end
    end
  end

  test "unrelated authored links, image credits and text are preserved" do
    html =
      ~s(<p>Toronto volunteers</p><a href="https://luma.com/pauseaitoronto">Events</a><a href="https://manifund.org.evil.invalid/">Other</a>)

    assert TorontoPresentation.national_donations(html, "fr") == html
  end

  test "authored governance portraits retain their name, role and heading bookmark" do
    html =
      TorontoPresentation.governance("""
      ## Our board

      ![Joseph Miller](/images/toronto-site/joseph.jpg)

      ### Joseph Miller

      Director of PauseAI UK

      ## Other work

      Keep this authored paragraph.
      """)

    assert html =~ ~s(<section class="toronto-board-member">)
    assert html =~ ~s(id="joseph-miller")
    assert html =~ "Director of PauseAI UK"
    assert html =~ "Keep this authored paragraph."
    assert html =~ ~s(src="/images/toronto-site/joseph.jpg")
  end
end
