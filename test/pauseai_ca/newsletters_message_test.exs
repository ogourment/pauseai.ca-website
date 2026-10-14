defmodule PauseAiCa.NewslettersMessageTest do
  use ExUnit.Case, async: true
  alias PauseAiCa.Newsletters.Message

  test "full preview includes both signup links and an explicitly inert withdrawal example" do
    html = Message.preview("Canadian updates", "# News\n\nA <script>bad()</script> update.")
    assert html =~ "Canadian updates"
    assert html =~ "<h1>News</h1>"
    assert html =~ "Preview: the unsubscribe link is an example"
    assert html =~ "https://example.org/newsletter-unsubscribe-preview"
    assert html =~ "Subscribe · English"
    assert html =~ "S’inscrire · Français"
    refute html =~ "<script>"
  end

  test "delivery envelope uses the personal unsubscribe URL in both alternatives" do
    url = "https://example.org/newsletters/withdraw?token=synthetic"
    {html, text} = Message.render("Updates", "News", url)
    assert html =~ "Unsubscribe"
    assert text =~ "Unsubscribe · Se désabonner"
    assert html =~ url and text =~ url
    assert text =~ "/en/participate?intent=newsletter"
    assert text =~ "/fr/participer?intent=newsletter"
    refute html =~ "newsletter-unsubscribe-preview"
    refute html =~ "Preview:"
  end

  test "newsletter unsubscribe is a small footer link and the body uses readable responsive styling" do
    {html, _} =
      Message.render(
        "Updates",
        "[Website](https://pauseai.ca/fr)",
        "https://example.org/withdraw",
        [],
        "fr"
      )

    assert html =~ "Se désabonner"
    refute html =~ "If the button does not work"
    refute html =~ "padding:14px 30px"
    refute html =~ "Impact"
    refute html =~ "Georgia"
    refute html =~ "You are receiving"
    assert html =~ "font-size:12px"
    assert html =~ "max-width:680px"
    assert html =~ "<h1"
    assert html =~ "Updates</h1>"
    assert html =~ "href=\"https://pauseai.ca/fr\""
  end
end
