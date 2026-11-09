defmodule PauseAiCa.MPOnboardingReturnTest do
  use PauseAiCa.DataCase, async: true
  alias PauseAiCa.Accounts.Onboarding
  alias PauseAiCa.Campaigns.Letter

  test "MP continuation preserves only bounded nonpersonal selectors" do
    path = "/fr/contacter-votre-depute?template=family-letter&revision=3&guide=1"
    context = Onboarding.context(%{"return_to" => path, "locale" => "fr"}, nil)
    uri = URI.parse(context["return_to"])
    assert uri.path == "/fr/contacter-votre-depute"

    assert URI.decode_query(uri.query) == %{
             "guide" => "1",
             "template" => "family-letter",
             "revision" => "3"
           }

    for unsafe <- [
          "https://example.org/en/contact-your-mp?guide=1",
          "//example.org/en/contact-your-mp?guide=1",
          "/en/contact-your-mp?guide=1&email=private@example.invalid",
          "/en/contact-your-mp?guide=1&body=private",
          "/en/contact-your-mp?guide=1&guide=0",
          "/en/contact-your-mp?template=../private",
          "/en/contact-your-mp?revision=-1",
          "/en/contact-your-mp?guide=1#private"
        ] do
      assert Onboarding.context(%{"return_to" => unsafe}, nil)["return_to"] == "/en/dashboard"
    end
  end

  test "personal placeholders are checked without blocking Markdown link labels" do
    for placeholder <- [
          "[Name]",
          "[MP name]",
          "[neighbourhood]",
          "[Your street address, Toronto]",
          "{{ sender_name }}",
          "[votre nom]"
        ] do
      assert Letter.unresolved_placeholders?(%Letter{
               to: "mp@example.invalid",
               subject: "Letter",
               body: "Replace #{placeholder}"
             })
    end

    refute Letter.unresolved_placeholders?(%Letter{
             to: "mp@example.invalid",
             subject: "Letter",
             body: "A [name](https://example.org) link."
           })
  end
end
