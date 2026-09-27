defmodule PauseAiCaWeb.ProtestRecapLive do
  use PauseAiCaWeb, :live_view

  @source "https://www.ledevoir.com/actualites/societe/1012274/montrealais-demandent-deceleration-developpement-ia"

  @impl true
  def mount(_, _, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("In Montréal, a call for a global pause on AI"),
       source: @source
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      promote_warning_shot={false}
      translated_path={
        if @locale == "fr",
          do: ~p"/en/montreal-protest-2026-09-26",
          else: ~p"/fr/manifestation-montreal-2026-09-26"
      }
    >
      <article id="protest-recap">
        <p class="sticky top-[var(--header-height)] z-30 bg-brand px-5 py-3 text-center font-heading text-sm font-bold uppercase tracking-[0.16em] text-stone-950">
          {gettext("Montréal · September 26, 2026")}
        </p>
        <section class="mx-auto max-w-5xl px-5 pt-14 pb-10">
          <h1 class="max-w-3xl font-heading text-5xl leading-[1.02] tracking-tight text-stone-950 sm:text-6xl">
            {gettext("In Montréal, a call for a global pause on AI")}
          </h1>
          <p id="protest-attendance" class="mt-7 max-w-3xl text-xl leading-9 text-stone-700">
            {gettext(
              "Around 40 people came together at Phillips Square in Montréal on September 26 to call for a global, coordinated pause in advanced AI development."
            )}
          </p>
          <.link
            id="protest-press-release"
            navigate={
              if @locale == "fr",
                do: ~p"/fr/manifestation-montreal-2026-09-26/communique",
                else: ~p"/en/montreal-protest-2026-09-26/press-release"
            }
            class="mt-5 inline-block font-semibold underline decoration-brand decoration-2 underline-offset-4"
          >{gettext("Read PauseAI Canada's press release")}</.link>
          <figure class="mt-10">
            <img
              id="protest-photo-3"
              src={~p"/images/protest-2026-09-26/clara-lacasse-3.jpg"}
              width="3000"
              height="2400"
              fetchpriority="high"
              alt={gettext("Demonstrators holding a PauseAI banner and signs at Phillips Square")}
              class="h-auto w-full rounded-xl"
            />
            <figcaption class="mt-3 text-sm text-stone-600">
              {gettext("At Phillips Square, Montréal. Photo: Clara Lacasse.")}
            </figcaption>
          </figure>
          <p id="protest-event-summary" class="mt-8 leading-8 text-stone-700">
            {gettext(
              "A protest organized by PauseAI Montr\u00e9al brought together around 40 people to draw attention to the risks of uncontrolled and uncontrollable AI. Scheduled from 1 to 2 p.m., the protest remained peaceful throughout, with several people joining during the event. Others engaged in many conversations with the organizers, and around a hundred educational brochures were distributed."
            )}
          </p>
          <div class="mt-10 border-l-4 border-brand bg-brand-wash p-7">
            <h2 class="font-heading text-2xl uppercase tracking-wide text-stone-950">
              {gettext("The call from Montréal")}
            </h2>
            <ul class="mt-4 list-disc space-y-3 pl-5 leading-7 text-stone-800">
              <li>
                {gettext(
                  "Recognize the development of artificial superintelligence as a national security threat."
                )}
              </li>
              <li>
                {gettext(
                  "Support an international treaty banning the development of superintelligent AI."
                )}
              </li>
              <li>
                {gettext(
                  "Coordinate a global pause so society has time to ensure that advanced AI remains safe and under democratic control."
                )}
              </li>
            </ul>
          </div>
        </section>
        <section class="border-y border-stone-200 bg-white">
          <div class="mx-auto max-w-5xl px-5 py-14">
            <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
              {gettext("Canada can help lead an international response")}
            </h2>
            <p class="mt-6 max-w-3xl leading-8 text-stone-700">
              {gettext(
                "We welcome Prime Minister Mark Carney's support for the international call for stronger oversight of frontier AI. We now ask him to go further: join the more than 30 Canadian MPs and senators whom ControlAI identifies as supporting recognition of superintelligent AI as a national security threat and an international prohibition on its development."
              )}
            </p>
            <blockquote class="mt-8 max-w-3xl border-l-4 border-brand pl-6 text-xl leading-9 text-stone-800">
              <p>
                “{gettext(
                  "We need to give ourselves more time to learn how to control AI systems before making them even more powerful. A pause is necessary."
                )}”
              </p>
              <footer class="mt-4 text-base font-semibold">
                {gettext("Jeremy Eliosoff, National Leader, PauseAI Canada")}
              </footer>
            </blockquote>
            <aside class="mt-10 border-t border-stone-200 pt-5 text-sm text-stone-600">
              <h3 class="font-semibold">{gettext("Media coverage")}</h3>
              <a
                id="protest-report-source"
                href={@source}
                rel="noreferrer"
                class="mt-2 inline-block underline decoration-brand decoration-2 underline-offset-4"
              >{gettext("Read the report in Le Devoir (French)")} ↗</a>
            </aside>
          </div>
        </section>
        <section id="protest-photos" class="mx-auto max-w-5xl px-5 pt-12">
          <div class="grid items-start gap-8 md:grid-cols-[3fr_2fr]">
            <figure>
              <img
                id="protest-photo-7"
                src={~p"/images/protest-2026-09-26/clara-lacasse-7.jpg"}
                width="3000"
                height="2400"
                loading="lazy"
                decoding="async"
                alt={gettext("Demonstrators holding signs calling for a worldwide pause on AI")}
                class="h-auto w-full rounded-xl"
              />
              <figcaption class="mt-3 text-sm text-stone-600">
                {gettext("Calling for a global pause. Photo: Clara Lacasse.")}
              </figcaption>
            </figure>
            <figure>
              <img
                id="protest-photo-14"
                src={~p"/images/protest-2026-09-26/clara-lacasse-14.jpg"}
                width="2400"
                height="3000"
                loading="lazy"
                decoding="async"
                alt={
                  gettext("Jeremy Eliosoff wearing a yellow PauseAI shirt at the Montréal protest")
                }
                class="h-auto w-full rounded-xl"
              />
              <figcaption class="mt-3 text-sm text-stone-600">
                {gettext("Jeremy Eliosoff. Photo: Clara Lacasse.")}
              </figcaption>
            </figure>
          </div>
        </section>
        <section class="mx-auto max-w-5xl px-5 py-16">
          <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
            {gettext("Take part")}
          </h2>
          <div class="mt-8 grid gap-6 md:grid-cols-2">
            <div class="flex flex-col gap-3 rounded-2xl border border-stone-200 bg-white p-6">
              <h3 class="font-heading text-2xl">{gettext("Write to your MP")}</h3>
              <p class="leading-7 text-stone-600">
                {gettext("Ask your MP to support an international agreement on advanced AI.")}
              </p>
              <.link
                id="protest-write-mp"
                navigate={
                  if @locale == "fr",
                    do: ~p"/fr/signal-d-alarme#letter",
                    else: ~p"/en/warning-shot#letter"
                }
                class="mt-auto inline-flex w-fit rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950"
              >{gettext("Prepare your letter")}</.link>
            </div>
            <div class="flex flex-col gap-3 rounded-2xl border border-stone-200 bg-white p-6">
              <h3 class="font-heading text-2xl">{gettext("Meet the Montréal community")}</h3>
              <p class="leading-7 text-stone-600">
                {gettext("Find upcoming gatherings and ways to take part with PauseAI Montréal.")}
              </p>
              <a
                href="https://luma.com/pauseaimtl"
                rel="noreferrer"
                class="mt-auto inline-flex w-fit rounded-full border-2 border-brand px-6 py-3 font-heading text-lg font-bold text-stone-950"
              >{gettext("Upcoming events")}</a>
            </div>
          </div>
        </section>
      </article>
    </Layouts.app>
    """
  end
end
