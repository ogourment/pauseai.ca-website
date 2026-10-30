defmodule PauseAiCaWeb.BlogLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Blog
  alias PauseAiCa.Blog.Markdown

  @impl true
  def mount(_, _, socket), do: {:ok, socket}
  @impl true
  def handle_params(params, _, socket) do
    locale = if socket.assigns.live_action in [:index_fr, :show_fr], do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    depth = if params["depth"] in ~w(summary details full), do: params["depth"], else: "authored"
    article = if params["slug"], do: Blog.published(params["slug"])
    article = if article && article.payload[locale], do: article
    alternate = if locale == "en", do: "fr", else: "en"

    translated_path =
      path(alternate) <>
        if(article && article.payload[alternate],
          do: "/" <> article.slug <> if(depth == "authored", do: "", else: "?depth=" <> depth),
          else: ""
        )

    socket =
      assign(socket,
        locale: locale,
        depth: depth,
        article: article,
        articles: Enum.filter(Blog.published(), & &1.payload[locale]),
        translated_path: translated_path,
        slug: params["slug"],
        page_title:
          if(article,
            do: Markdown.document(article.payload[locale], locale).title,
            else: gettext("Blog")
          )
      )

    {:noreply, socket}
  end

  def path("fr"), do: "/fr/blogue"
  def path(_), do: "/en/blog"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={@translated_path}
    >
      <div class="mx-auto max-w-3xl px-5 py-12">
        <nav :if={@article} class="mb-7">
          <.link navigate={path(@locale)} class="underline">{gettext("All articles")}</.link>
        </nav>
        <PauseAiCaWeb.BlogContent.article
          :if={@article}
          edition={@article.payload[@locale]}
          locale={@locale}
          depth={@depth}
        />
        <section :if={is_nil(@article) and is_nil(@slug)}>
          <h1 class="font-heading text-4xl">{gettext("Blog")}</h1>
          <p class="mt-4 text-lg">
            {gettext("Read an article and expand the sections you want to explore.")}
          </p>
          <p :if={@articles == []} class="mt-8">
            {gettext("Articles will appear here when published.")}
          </p>
          <article :for={article <- @articles} class="mt-8 space-y-3 border-t border-stone-300 pt-6">
            <h2 class="text-2xl font-semibold">
              <.link navigate={path(@locale) <> "/" <> article.slug} class="underline">{Markdown.document(
                article.payload[@locale]
              ).title}</.link>
            </h2>
            <div class="prose prose-stone max-w-none break-words leading-7">
              {raw(Markdown.document(article.payload[@locale], @locale).intro)}
            </div>
          </article>
        </section>
        <section :if={is_nil(@article) and @slug}>
          <h1 class="text-3xl font-semibold">{gettext("Article unavailable")}</h1>
          <.link navigate={path(@locale)} class="mt-5 inline-block underline">{gettext("All articles")}</.link>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
