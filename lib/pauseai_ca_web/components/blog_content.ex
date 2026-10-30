defmodule PauseAiCaWeb.BlogContent do
  use PauseAiCaWeb, :html
  alias PauseAiCa.Blog.Markdown
  attr :edition, :map, required: true
  attr :id, :string, default: "blog"
  attr :depth, :string, default: "authored"
  attr :locale, :string, default: "en"

  def article(assigns) do
    assigns = assign(assigns, :document, Markdown.document(assigns.edition, assigns.locale))

    ~H"""
    <article id={@id <> "-article"} class="space-y-7">
      <h1 class="font-heading text-4xl leading-tight sm:text-5xl">{@document.title}</h1>
      <div id={@id <> "-intro"} class="prose prose-stone max-w-none break-words text-lg leading-8">
        {raw(@document.intro)}
      </div>
      <.sections sections={@document.sections} depth={@depth} nesting={0} prefix={@id} />
    </article>
    """
  end

  def preview(source) do
    article(%{
      __changed__: nil,
      edition: %{"markdown" => source},
      id: "blog-preview",
      depth: "authored",
      locale: "en"
    })
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp expanded?(_section, "full", _nesting), do: true
  defp expanded?(_section, "details", nesting), do: nesting == 0
  defp expanded?(_section, "summary", _nesting), do: false
  defp expanded?(section, _depth, _nesting), do: section.open?

  attr :sections, :list, required: true
  attr :depth, :string, required: true
  attr :nesting, :integer, required: true
  attr :prefix, :string, required: true

  def sections(assigns) do
    ~H"""
    <details
      :for={section <- @sections}
      id={@prefix <> "-section-" <> section.id}
      open={expanded?(section, @depth, @nesting)}
      class="my-5 rounded-xl border border-stone-300 p-4 sm:p-5"
    >
      <summary class="cursor-pointer py-2 font-heading text-xl font-semibold">
        <span role="heading" aria-level={section.level}>{section.title}</span>
      </summary>
      <div class="prose prose-stone mt-4 max-w-none break-words">{raw(section.html)}</div>
      <.sections sections={section.sections} depth={@depth} nesting={@nesting + 1} prefix={@prefix} />
    </details>
    """
  end
end
