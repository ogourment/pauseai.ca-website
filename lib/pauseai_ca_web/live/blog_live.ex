defmodule PauseAiCaWeb.BlogLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Blog

  @impl true
  def mount(_, _, socket), do: {:ok, socket}
  @impl true
  def handle_params(params, _, socket) do
    locale = if socket.assigns.live_action in [:index_fr, :show_fr], do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    depth = if params["depth"] in ~w(summary details full), do: params["depth"], else: "summary"
    article = if params["slug"], do: Blog.published(params["slug"])
    article = if article && article.payload[locale], do: article
    alternate = if locale == "en", do: "fr", else: "en"

    translated_path =
      path(alternate) <>
        if(article && article.payload[alternate],
          do: "/" <> article.slug <> "?depth=" <> depth,
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
        page_title: if(article, do: article.payload[locale]["title"], else: gettext("Blog"))
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
          depth={@depth}
        >
          <:depth_controls>
            <nav aria-label={gettext("Reading depth")} class="mb-8 flex flex-wrap gap-2">
              <.link
                :for={
                  {depth, label} <- [
                    {"summary", gettext("In brief")},
                    {"details", gettext("More details")},
                    {"full", gettext("Everything")}
                  ]
                }
                patch={path(@locale) <> "/" <> @article.slug <> "?depth=" <> depth}
                aria-current={if @depth == depth, do: "true", else: "false"}
                class={[
                  "min-h-11 rounded-lg border px-4 py-3 font-semibold",
                  if(@depth == depth, do: "border-brand bg-brand-wash", else: "border-stone-300")
                ]}
              >{label}</.link>
            </nav>
          </:depth_controls>
        </PauseAiCaWeb.BlogContent.article>
        <section :if={is_nil(@article) and is_nil(@slug)}>
          <h1 class="font-heading text-4xl">{gettext("Blog")}</h1>
          <p class="mt-4 text-lg">
            {gettext("Read the summary, explore the details or open the full article.")}
          </p>
          <p :if={@articles == []} class="mt-8">
            {gettext("Articles will appear here when published.")}
          </p>
          <article :for={article <- @articles} class="mt-8 space-y-3 border-t border-stone-300 pt-6">
            <h2 class="text-2xl font-semibold">
              <.link navigate={path(@locale) <> "/" <> article.slug} class="underline">{article.payload[
                @locale
              ]["title"]}</.link>
            </h2>
            <p class="whitespace-pre-line leading-7">{article.payload[@locale]["summary"]}</p>
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
