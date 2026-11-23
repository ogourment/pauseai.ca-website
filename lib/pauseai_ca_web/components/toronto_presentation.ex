defmodule PauseAiCaWeb.TorontoPresentation do
  @moduledoc "Host presentation and national donation destinations for the Toronto chapter."
  alias PauseAiCa.Incubators.ChapterMarkdown

  def donate_path("fr"), do: "/fr/faire-un-don"
  def donate_path(_), do: "/en/donate"

  # Only rewrite hrefs in already sanitized host-rendered Markdown. Other links,
  # image credits and chapter content remain authored by the chapter manager.
  def national_donations(html, locale) do
    Regex.replace(~r/href="([^"]+)"/, html, fn attribute, url ->
      uri = URI.parse(url)

      if url in ["/en/donate", "/fr/faire-un-don"] or
           uri.host in ["donate.stripe.com", "buy.stripe.com", "manifund.org"] or
           Regex.match?(
             ~r{\A(?:https://pauseaitoronto\.info)?/(?:donate(?:\.html)?|groups/toronto/pages/donate)(?:[?#].*)?\z},
             url
           ) do
        ~s(href="#{donate_path(locale)}")
      else
        attribute
      end
    end)
  end

  def governance(source) do
    source
    |> ChapterMarkdown.render_page("toronto")
    |> then(fn html ->
      # Group only the authored portrait/name/title sequence. Heading IDs and
      # all following content are preserved, including non-board paragraphs.
      Regex.replace(
        ~r{(<p><img [^>]+></p>)\s*(<h3[^>]*>.*?</h3>)\s*(<p>.*?</p>)}s,
        html,
        ~s(<section class="toronto-board-member">\\1<div>\\2\\3</div></section>)
      )
    end)
  end
end
