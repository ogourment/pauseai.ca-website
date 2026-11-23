defmodule PauseAiCa.Incubators.ChapterMarkdown do
  @moduledoc "Chapter Markdown rendered identically in the editor preview and on the public page."
  use Gettext, backend: PauseAiCaWeb.Gettext

  @toronto "/images/protest-2026-11-14/toronto-crossing.jpg"
  @montreal "/images/protest-2026-11-14/clara-lacasse-23.jpg"

  @toronto_portrait_sizes %{
    "/images/toronto-site/muhammad.jpg" => 560,
    "/images/toronto-site/daniel.jpg" => 480,
    "/images/toronto-site/ilyass.jpg" => 480
  }

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

  def render(source, chapter_slug \\ nil) do
    doc = parse(source, chapter_slug)

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
      intro: html(doc, intro, chapter_slug),
      photo: html(doc, photo, chapter_slug),
      caption: html(doc, caption, chapter_slug),
      body: html(doc, body, chapter_slug)
    }
  end

  def toronto_landing_sections(source) do
    case MDEx.parse_document!(source) do
      %{nodes: [%MDEx.Heading{level: 1} | _]} = doc ->
        case sections(prepare(doc, "toronto"), %{"Get involved" => "do", "What we want" => "want"}) do
          [_, _ | _] = sections -> sections
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def toronto_plan_sections(source),
    do: source |> parse("toronto") |> sections(%{"Theory of change" => "theory"})

  defp sections(doc, aliases) do
    existing =
      doc.nodes
      |> Enum.map(&heading_text/1)
      |> MapSet.new(&String.downcase/1)

    {sections, current} =
      Enum.reduce(doc.nodes, {[], []}, fn
        %MDEx.Heading{level: 2} = heading, {sections, [_ | _] = current} ->
          {[Enum.reverse(current) | sections], [heading]}

        node, {sections, current} ->
          {sections, [node | current]}
      end)

    for nodes <- Enum.reverse([Enum.reverse(current) | sections]), nodes != [] do
      anchor = Map.get(aliases, heading_text(hd(nodes)))
      anchor = if anchor && !MapSet.member?(existing, anchor), do: anchor
      %{alias: anchor, html: html(doc, nodes, "toronto")}
    end
  end

  defp heading_text(%MDEx.Heading{nodes: [%MDEx.Text{literal: text}]}), do: text
  defp heading_text(_), do: ""

  def render_page(source, chapter_slug) do
    source
    |> parse(chapter_slug)
    |> render_html(chapter_slug)
  end

  defp parse(source, chapter_slug), do: source |> MDEx.parse_document!() |> prepare(chapter_slug)

  defp prepare(doc, chapter_slug) do
    doc
    |> MDEx.Document.update_nodes(MDEx.Image, fn image ->
      if allowed_image?(image.url, chapter_slug), do: image, else: %MDEx.Text{literal: ""}
    end)
    |> MDEx.Document.update_nodes(MDEx.Heading, fn
      %MDEx.Heading{level: 1} = heading when is_binary(chapter_slug) -> %{heading | level: 2}
      heading -> heading
    end)
  end

  defp render_options(nil) do
    [render: [escape: true], sanitize: [url_schemes: ["https", "http", "mailto"]]]
  end

  defp render_options(_chapter_slug) do
    [
      extension: [header_id_prefix: ""],
      render: [escape: true],
      sanitize: [
        url_schemes: ["https", "http", "mailto"],
        add_tag_attributes: Map.new(~w(h1 h2 h3 h4 h5 h6 a), &{&1, ["id"]})
      ]
    ]
  end

  defp allowed_image?(url, "toronto") do
    url in [@toronto, @montreal] or
      Regex.match?(
        ~r{\A/images/toronto-site/(?:[a-zA-Z0-9_-]+/)*[a-zA-Z0-9_.-]+\.(?:jpg|jpeg|png|webp|gif|svg)\z},
        url
      )
  end

  defp allowed_image?(url, _), do: url in [@toronto, @montreal]

  defp html(_doc, [], _chapter_slug), do: ""

  defp html(doc, nodes, chapter_slug) do
    %{doc | nodes: nodes}
    |> render_html(chapter_slug)
  end

  defp render_html(doc, chapter_slug) do
    html = MDEx.to_html!(doc, render_options(chapter_slug))

    if chapter_slug == "toronto" do
      Enum.reduce(@toronto_portrait_sizes, html, fn {path, size}, html ->
        String.replace(
          html,
          ~s(<img src="#{path}"),
          ~s(<img src="#{path}" width="#{size}" height="#{size}")
        )
      end)
    else
      html
    end
  end
end
