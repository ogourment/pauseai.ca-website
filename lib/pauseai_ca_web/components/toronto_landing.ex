defmodule PauseAiCaWeb.TorontoLanding do
  @moduledoc "Chapter-owned presentation for Toronto's editable Markdown homepage."
  use Phoenix.Component

  attr :sections, :list, required: true
  attr :name, :string, required: true
  attr :lang, :string, required: true

  def landing(assigns) do
    [intro | sections] = assigns.sections
    assigns = assign(assigns, intro: intro, sections: sections)

    ~H"""
    <article lang={@lang} class="toronto-front">
      <header class="toronto-hero">
        <div class="toronto-hero-copy">
          <h1>{@name}</h1>
          {Phoenix.HTML.raw(@intro.html)}
        </div>
        <figure lang="en">
          <img
            src="/images/protest-2026-11-14/toronto-crossing.jpg"
            alt="Marchers crossing a downtown Toronto street with signs calling for an AI treaty."
            fetchpriority="high"
          />
          <figcaption>Toronto AI Treaty March · PauseAI Toronto</figcaption>
        </figure>
      </header>
      <section :for={section <- @sections} class="toronto-story">
        <span :if={section.alias} id={section.alias} class="chapter-fragment-alias" aria-hidden="true"></span>
        {Phoenix.HTML.raw(section.html)}
      </section>
    </article>
    """
  end
end
