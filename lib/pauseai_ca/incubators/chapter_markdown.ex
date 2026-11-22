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
    doc =
      source
      |> MDEx.parse_document!()
      |> MDEx.Document.update_nodes(MDEx.Image, fn image ->
        if image.url in [@toronto, @montreal], do: image, else: %MDEx.Text{literal: ""}
      end)

    {intro, rest} =
      Enum.split_while(doc.nodes, fn
        %MDEx.Paragraph{nodes: [%MDEx.Image{}]} -> false
        _ -> true
      end)

    {photo, caption, body} =
      case rest do
        [image, %MDEx.Paragraph{nodes: [%MDEx.Emph{}]} = caption | body] ->
          {[image], [caption], body}

        [image | body] ->
          {[image], [], body}

        [] ->
          {[], [], []}
      end

    %{
      intro: html(doc, intro),
      photo: html(doc, photo),
      caption: html(doc, caption),
      body: html(doc, body)
    }
  end

  defp html(_doc, []), do: ""

  defp html(doc, nodes) do
    %{doc | nodes: nodes}
    |> MDEx.to_html!(render: [escape: true], sanitize: [url_schemes: ["https", "http", "mailto"]])
  end
end
