defmodule PauseAiCa.Incubators.ChapterMarkdown do
  @moduledoc "Chapter Markdown rendered identically in the editor preview and on the public page."
  use Gettext, backend: PauseAiCaWeb.Gettext

  @toronto "/images/protest-2026-11-14/toronto-crossing.jpg"
  @montreal "/images/protest-2026-11-14/clara-lacasse-23.jpg"

  def images do
    [
      {@toronto,
       gettext(
         "Toronto marchers crossing a downtown street with signs calling for an AI treaty."
       ), gettext("Photo source: PauseAI Toronto.")},
      {@montreal, gettext("Marchers with a megaphone and signs calling for a treaty now."),
       gettext("Voices for an AI treaty. Photo: Clara Lacasse.")}
    ]
  end

  def render(source) do
    source
    |> MDEx.parse_document!()
    |> MDEx.Document.update_nodes(MDEx.Image, fn image ->
      if image.url in [@toronto, @montreal], do: image, else: %MDEx.Text{literal: ""}
    end)
    |> MDEx.to_html!(render: [escape: true], sanitize: [url_schemes: ["https", "http", "mailto"]])
  end
end
