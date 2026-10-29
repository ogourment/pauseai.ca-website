defmodule PauseAiCaWeb.BlogContent do
  use PauseAiCaWeb, :html
  attr :edition, :map, required: true
  attr :id, :string, default: "blog"
  attr :depth, :string, default: "summary"

  slot :depth_controls

  def article(assigns) do
    ~H"""
    <article id={@id <> "-article"} class="space-y-7">
      <h1 class="font-heading text-4xl leading-tight sm:text-5xl">{@edition["title"]}</h1>
      <p id={@id <> "-summary"} class="whitespace-pre-line text-xl leading-8">
        {@edition["summary"]}
      </p>
      {render_slot(@depth_controls)}
      <details
        id={@id <> "-details"}
        open={@depth in ["details", "full"]}
        class="rounded-xl border border-stone-300 p-5"
      >
        <summary class="cursor-pointer py-2 text-xl font-semibold">{gettext("More details")}</summary>
        <div class="prose prose-stone mt-5 max-w-none break-words">
          {raw(PauseAiCa.Mail.Render.html(@edition["details"]))}
        </div>
        <details
          id={@id <> "-full"}
          open={@depth == "full"}
          class="mt-7 border-t border-stone-300 pt-4"
        >
          <summary class="cursor-pointer py-2 text-xl font-semibold">{gettext("Everything")}</summary>
          <div class="prose prose-stone mt-5 max-w-none break-words">
            {raw(PauseAiCa.Mail.Render.html(@edition["full"]))}
          </div>
        </details>
      </details>
    </article>
    """
  end
end
