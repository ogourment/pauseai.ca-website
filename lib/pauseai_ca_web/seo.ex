defmodule PauseAiCaWeb.SEO do
  @moduledoc "Published public pages and their canonical bilingual search metadata."
  use Gettext, backend: PauseAiCaWeb.Gettext
  import Ecto.Query
  alias PauseAiCaWeb.{ChapterPagesLive, Site}
  alias PauseAiCa.{Blog, Incubators, MPTemplates, Repo}

  def for_conn(conn) do
    locale = conn.assigns[:locale] || "en"
    path = if conn.request_path == "/", do: "/#{locale}", else: conn.request_path
    entry = Enum.find(static_entries(locale), &(&1.path == path)) || dynamic_entry(path, locale)
    public? = entry != nil and (is_nil(conn.status) or conn.status < 400)
    content_locale = if public?, do: Map.get(entry, :locale, locale), else: locale
    canonical = if public?, do: Site.url(content_locale, entry.path)
    image = if public?, do: Map.get(entry, :image), else: nil
    name = Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn -> gettext("PauseAI Canada") end)

    %{
      title: if(public?, do: entry.title, else: name),
      description: if(public?, do: entry.description),
      canonical: canonical,
      alternates: if(public?, do: alternates(entry), else: []),
      site_name: name,
      locale: if(content_locale == "fr", do: "fr_CA", else: "en_CA"),
      image: Site.url(content_locale, image || "/images/social-preview.png"),
      noindex: PauseAiCa.Environment.badged?() or not public?,
      type: if(public? and entry.kind == :article, do: "article", else: "website"),
      structured_json:
        if(public? and entry.path in ["/en", "/fr"], do: organization(locale, name))
    }
  end

  def entries, do: Enum.flat_map(["en", "fr"], &(static_entries(&1) ++ published_entries(&1)))

  def alternates(entry) do
    Enum.map(entry.paths, fn {locale, path} ->
      %{language: locale <> "-CA", url: Site.url(locale, path)}
    end)
  end

  defp static_entries(locale) do
    Gettext.with_locale(PauseAiCaWeb.Gettext, locale, fn ->
      [
        {"", "", gettext("PauseAI Canada — A global pause on advanced AI"),
         gettext(
           "Join PauseAI Canada in calling for a global pause on advanced AI. Learn about the risks, contact your MP and get involved locally."
         )},
        {"/about", "/a-propos", gettext("About PauseAI Canada"),
         gettext(
           "Meet the Canadian movement calling for international safeguards and a global pause on advanced AI."
         )},
        {"/strategy", "/strategie", gettext("Our strategy"),
         gettext(
           "How PauseAI Canada works toward an internationally coordinated pause on advanced AI through public action and political engagement."
         )},
        {"/privacy", "/confidentialite", gettext("Privacy policy"),
         gettext(
           "How PauseAI Canada handles personal information, website activity and communication preferences."
         )},
        {"/groups", "/groupes", gettext("Local groups"),
         gettext(
           "Find a PauseAI Canada group or incubator, join a local waitlist or offer to help organize in your community."
         )},
        {"/donate", "/faire-un-don", gettext("Support PauseAI Canada"),
         gettext(
           "Help fund local organizing and PauseAI Canada's work toward international safeguards for advanced AI."
         )},
        {"/participate", "/participer", gettext("Get involved with PauseAI Canada"),
         gettext("Get updates, join a local group or offer your help with PauseAI Canada.")},
        {"/learn", "/comprendre", gettext("Understand the risks of advanced AI"),
         gettext(
           "Explore research, questions and learning resources about advanced AI risks and the case for a global pause."
         )},
        {"/blog", "/blogue", gettext("PauseAI Canada articles"),
         gettext(
           "Read news, analysis and updates from PauseAI Canada, with practical ways to get involved."
         )},
        {"/contact-your-mp", "/contacter-votre-depute",
         gettext("Contact your MP about AI safety"),
         gettext(
           "Write to your Member of Parliament about advanced AI risks and international safeguards using PauseAI Canada's letter tool."
         )},
        {"/warning-shot", "/signal-d-alarme", gettext("Warning Shot Protocol"),
         gettext(
           "Understand the Warning Shot Protocol and take action on advanced AI risks with PauseAI Canada."
         )},
        {"/our-actions", "/nos-actions", gettext("Our actions"),
         gettext(
           "Read about PauseAI Canada's Montréal and Toronto marches, with photographs and Montréal press releases."
         )},
        {"/montreal-protest-2026-11-14/press-release",
         "/manifestation-montreal-2026-11-14/communique",
         gettext("Montréal march press release — November 16, 2026"),
         gettext(
           "PauseAI Canada's November 16 press release following the November 14 Montréal march for an AI treaty."
         )},
        {"/montreal-protest-2026-09-26", "/manifestation-montreal-2026-09-26",
         gettext("Montréal protest — September 26, 2026"),
         gettext("Read the recap of PauseAI Canada's September 26, 2026 protest in Montréal.")},
        {"/montreal-protest-2026-09-26/press-release",
         "/manifestation-montreal-2026-09-26/communique",
         gettext("Montréal protest press release"),
         gettext("The press release for PauseAI Canada's September 26, 2026 protest in Montréal.")},
        {"/rogue-agent", "/agent-rebelle", gettext("Rogue Agent"),
         gettext(
           "Explore AI control and safety questions through PauseAI Canada's interactive Rogue Agent game."
         )}
      ]
      |> Enum.map(fn {en, fr, title, description} ->
        paths = %{"en" => "/en" <> en, "fr" => "/fr" <> fr}

        %{
          path: paths[locale],
          paths: paths,
          title: title,
          description: description,
          kind: :website
        }
      end)
    end)
  end

  defp published_entries(locale) do
    articles =
      for article <- Blog.published(), entry = article_entry(article, locale), entry, do: entry

    templates =
      Repo.all(
        from t in MPTemplates.Template, where: not is_nil(t.published_revision), select: t.slug
      )

    articles ++ Enum.flat_map(templates, &List.wrap(template_entry(&1, locale)))
  end

  defp dynamic_entry(path, locale) do
    case String.split(path, "/", trim: true) do
      [^locale, section, slug] when section in ["blog", "blogue"] ->
        if path == blog_path(locale) <> "/" <> slug,
          do: article_entry(Blog.published(slug), locale)

      [^locale, section, slug] when section in ["mp-templates", "modeles-de-lettre"] ->
        if path == template_path(locale) <> "/" <> slug, do: template_entry(slug, locale)

      ["groups", slug] ->
        chapter_entry(path, slug, nil, locale)

      ["groups", slug, "pages", page] ->
        chapter_entry(path, slug, page, locale)

      _ ->
        nil
    end
  end

  defp chapter_entry(path, slug, page_slug, locale) do
    with true <- ChapterPagesLive.available?(),
         true <- Application.get_env(:pauseai_ca, :incubators_enabled, false),
         %{slug: ^slug} = chapter <- Incubators.published_chapter(slug),
         true <- path == chapter_path(slug, page_slug) do
      chapter_entry_for_page(chapter, page_slug, path, locale)
    else
      _ -> nil
    end
  end

  defp chapter_entry_for_page(chapter, nil, path, locale) do
    editions =
      for lang <- ["en", "fr"],
          String.trim(chapter.content[lang] || "") != "",
          into: %{},
          do: {lang, chapter_home_path(path, lang)}

    language =
      if Map.has_key?(editions, locale),
        do: locale,
        else: Enum.find(["en", "fr"], &Map.has_key?(editions, &1))

    if language do
      chapter_entry_data(
        chapter,
        editions,
        language,
        chapter_name(chapter, locale),
        chapter_summary(chapter, language)
      )
    end
  end

  defp chapter_entry_for_page(chapter, slug, path, _locale) when slug != "home" do
    case Enum.find(Incubators.published_chapter_pages(chapter.group_id), &(elem(&1, 0) == slug)) do
      {^slug, %{"body" => body, "title" => title}} ->
        chapter_entry_data(
          chapter,
          %{"en" => path},
          "en",
          title <> " · " <> chapter_name(chapter, "en"),
          chapter_page_description(chapter.slug, slug, body)
        )

      _ ->
        nil
    end
  end

  defp chapter_entry_for_page(_chapter, _slug, _path, _locale), do: nil

  defp chapter_entry_data(chapter, paths, language, title, description) do
    %{
      path: paths[language],
      paths: paths,
      title: title,
      description: description,
      locale: language,
      kind: :website,
      image: if(chapter.slug == "toronto", do: "/images/protest-2026-11-14/toronto-crossing.jpg")
    }
  end

  defp chapter_path(slug, nil), do: "/groups/" <> slug
  defp chapter_path(slug, page), do: chapter_path(slug, nil) <> "/pages/" <> page
  defp chapter_home_path(path, "fr"), do: path <> "?locale=fr"
  defp chapter_home_path(path, _), do: path
  defp chapter_name(chapter, "fr"), do: chapter.name_fr
  defp chapter_name(chapter, _), do: chapter.name_en

  defp chapter_summary(chapter, language) do
    summary = if language == "fr", do: chapter.summary_fr, else: chapter.summary_en

    case plain_text(summary || "") do
      "" -> chapter_home_description(chapter, language)
      description -> description
    end
  end

  defp chapter_home_description(%{slug: "toronto"}, "en"),
    do:
      "Meet PauseAI Toronto, learn why it calls for an AI treaty, and find local events and ways to get involved."

  defp chapter_home_description(chapter, language),
    do: markdown_summary(chapter.content[language])

  defp chapter_page_description("toronto", "governance", _),
    do: "Meet the people on PauseAI Toronto’s board and read the chapter’s donation policies."

  defp chapter_page_description("toronto", "donate", _),
    do:
      "Support PauseAI Toronto with a monthly or one-off gift. Read about its funding plans and donation policies."

  defp chapter_page_description(_chapter, _slug, source), do: markdown_summary(source)

  defp markdown_summary(source) do
    sections = MDEx.parse_document!(source).nodes

    Enum.find_value(sections, fn
      %MDEx.Paragraph{nodes: nodes} ->
        if Enum.any?(nodes, &match?(%MDEx.Text{literal: <<_::binary>>}, &1)) do
          case plain_text(markdown_text(nodes)) do
            "" -> nil
            description -> description
          end
        end

      _ ->
        nil
    end) ||
      Enum.find_value(sections, fn
        %MDEx.Heading{nodes: nodes} -> plain_text(markdown_text(nodes))
        _ -> nil
      end)
  end

  defp markdown_text(nodes) do
    Enum.map_join(nodes, fn
      %MDEx.Text{literal: text} -> text
      %MDEx.Image{} -> ""
      %MDEx.SoftBreak{} -> " "
      %MDEx.LineBreak{} -> " "
      %{nodes: children} -> markdown_text(children)
      _ -> ""
    end)
  end

  defp article_entry(nil, _), do: nil

  defp article_entry(article, locale) do
    if edition = article.payload[locale] do
      document = Blog.Markdown.document(edition, locale)

      paths =
        for lang <- ["en", "fr"],
            article.payload[lang],
            into: %{},
            do: {lang, blog_path(lang) <> "/" <> article.slug}

      %{
        path: paths[locale],
        paths: paths,
        title: document.title,
        description: document.summary,
        kind: :article
      }
    end
  end

  defp template_entry(slug, locale) do
    case MPTemplates.published(slug, locale) do
      {:ok, template} ->
        paths =
          for lang <- ["en", "fr"],
              match?({:ok, _}, MPTemplates.published(slug, lang)),
              into: %{},
              do: {lang, template_path(lang) <> "/" <> slug}

        %{
          path: paths[locale],
          paths: paths,
          title: template.title,
          description: plain_text(template.purpose),
          kind: :website
        }

      _ ->
        nil
    end
  end

  defp plain_text(value) do
    value |> String.replace(~r/\s+/u, " ") |> String.trim() |> String.slice(0, 170)
  end

  defp blog_path("en"), do: "/en/blog"
  defp blog_path("fr"), do: "/fr/blogue"
  defp template_path("en"), do: "/en/mp-templates"
  defp template_path("fr"), do: "/fr/modeles-de-lettre"

  defp organization(locale, name) do
    home = Site.url(locale, "/")

    Jason.encode!(%{
      "@context" => "https://schema.org",
      "@graph" => [
        %{
          "@type" => "Organization",
          "@id" => Site.url("en", "/en#organization"),
          "name" => "PauseAI Canada",
          "alternateName" => "PauseIA Canada",
          "url" => Site.url("en", "/en"),
          "logo" => Site.url("en", "/images/pauseai-canada-logo.png"),
          "sameAs" => [
            "https://www.instagram.com/pauseaicanada/",
            "https://bsky.app/profile/pauseaicanada.bsky.social",
            "https://x.com/pauseaicanada"
          ]
        },
        %{
          "@type" => "WebSite",
          "@id" => home <> "#website",
          "name" => name,
          "url" => home,
          "inLanguage" => locale <> "-CA"
        }
      ]
    })
  end
end
