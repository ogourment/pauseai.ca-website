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
      class="bg-amber-300 px-3 py-6 text-center text-stone-950 sm:py-8"
    >
      <div class="mx-auto flex max-w-6xl flex-col items-center gap-4">
        <p class="font-heading text-[3.5rem] font-bold leading-[1.05] sm:text-[5rem]">
          <time datetime="2026-11-14">{gettext("November 14 marches:")}</time>
        </p>
        <div class="flex flex-wrap justify-center gap-x-8 gap-y-2">
          <a
            id="march-montreal"
            href="https://luma.com/g93q6ksk?tk=EYSylQ"
            class="inline-flex min-h-11 items-center text-[1.75rem] font-semibold text-stone-950 underline underline-offset-4 hover:text-stone-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-950 sm:text-4xl"
          >Montréal</a>
          <a
            id="march-toronto"
            href="https://luma.com/20vit6m2"
            class="inline-flex min-h-11 items-center text-[1.75rem] font-semibold text-stone-950 underline underline-offset-4 hover:text-stone-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-stone-950 sm:text-4xl"
          >Toronto</a>
        </div>
      </div>
    </aside>
    """
  end
end
