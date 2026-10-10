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
    assert text =~ "/en/learn#newsletter-heading"
    assert text =~ "/fr/comprendre#newsletter-heading"
    refute html =~ "newsletter-unsubscribe-preview"
    refute html =~ "Preview:"
  end
end
