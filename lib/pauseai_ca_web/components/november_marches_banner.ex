defmodule PauseAiCaWeb.NovemberMarchesBanner do
  use PauseAiCaWeb, :html

  # November 15 at midnight in Montréal and Toronto (EST).
  @ends_at ~U[2026-11-15 05:00:00Z]
  attr :now, :any, default: nil

  def banner(assigns) do
    assigns =
      assign(
        assigns,
        :active?,
        DateTime.compare(assigns.now || DateTime.utc_now(), @ends_at) == :lt
      )

    ~H"""
    <aside
      :if={@active?}
      id="november-marches-banner"
      aria-label={gettext("November 14 marches")}
      class="bg-stone-950 px-3 py-1 text-sm text-white"
    >
      <div class="mx-auto flex max-w-6xl flex-wrap items-center justify-center gap-x-4">
        <span class="font-semibold"><time datetime="2026-11-14">{gettext("November 14 marches:")}</time></span>
        <a
          id="march-montreal"
          href="https://luma.com/g93q6ksk?tk=EYSylQ"
          class="inline-flex min-h-7 items-center text-white underline underline-offset-4 hover:text-amber-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
        >Montréal</a>
        <a
          id="march-toronto"
          href="https://luma.com/20vit6m2"
          class="inline-flex min-h-7 items-center text-white underline underline-offset-4 hover:text-amber-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white"
        >Toronto</a>
      </div>
    </aside>
    """
  end
end
