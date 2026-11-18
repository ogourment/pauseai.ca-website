defmodule PauseAiCaWeb.ActionsLive do
  use PauseAiCaWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    {:ok, assign(socket, locale: locale, page_title: gettext("Our actions"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      show_current_breadcrumb={false}
      promote_warning_shot={false}
      translated_path={if @locale == "fr", do: ~p"/en/our-actions", else: ~p"/fr/nos-actions"}
    >
      <article id="our-actions" class="mx-auto max-w-6xl px-3 py-12 sm:px-5 sm:py-16">
        <h1 class="font-heading text-4xl leading-tight text-stone-950 sm:text-5xl">
          {gettext("Our actions")}
        </h1>
        <p class="mt-5 max-w-3xl text-xl leading-8 text-stone-700">
          {gettext("Marches and public actions for an international treaty on advanced AI.")
          |> String.replace(~r/ (?=[^ ]+$)/u, "\u00A0")}
        </p>
        <nav
          class="mt-7 flex flex-wrap gap-x-6 gap-y-3 text-sm font-semibold"
          aria-label={gettext("Our actions")}
        >
          <a
            href="#montreal-2026-11-14"
            class="whitespace-nowrap underline decoration-brand underline-offset-4"
          >{gettext("Montréal · Nov. 14")}</a>
          <a
            href="#toronto-2026-11-14"
            class="whitespace-nowrap underline decoration-brand underline-offset-4"
          >{gettext("Toronto · Nov. 14")}</a>
          <a
            href="#montreal-2026-09-26"
            class="whitespace-nowrap underline decoration-brand underline-offset-4"
          >{gettext("Montréal · Sept. 26")}</a>
        </nav>
        <section id="montreal-2026-11-14" class="mt-12 scroll-mt-40 border-t border-stone-300 pt-10">
          <h2 class="font-heading text-3xl text-stone-950">
            Montréal ·
            <time datetime="2026-11-14" class="inline-block max-w-full">{gettext("November 14, 2026")}</time>
          </h2>
          <div class="mt-6 grid items-start gap-8 lg:grid-cols-2">
            <figure>
              <img
                src={~p"/images/protest-2026-11-14/clara-lacasse-8.jpg"}
                srcset={"#{~p"/images/protest-2026-11-14/clara-lacasse-8-small.jpg"} 640w, #{~p"/images/protest-2026-11-14/clara-lacasse-8.jpg"} 1200w"}
                sizes="(min-width:1024px) 540px, calc(100vw - 24px)"
                width="1200"
                height="960"
                alt={
                  gettext(
                    "Marchers carrying PauseAI signs and a banner through Montréal on November 14."
                  )
                }
                class="h-auto w-full rounded-xl"
                fetchpriority="high"
              />
              <figcaption class="mt-2 text-sm text-stone-600">
                <a
                  href="https://drive.google.com/drive/folders/1slbLd1MK7VrmGv4iDeBUdCCuKZ4SGKW7"
                  class="underline"
                >{gettext("Photo: Clara Lacasse. November 14, 2026.")}</a>
              </figcaption>
            </figure>
            <div>
              <p class="mt-4 leading-8 text-stone-700">
                {gettext(
                  "The Coalition for an AI Treaty brought together PauseAI Canada, Stop the AI Race and Horizon Omega for a march in Montréal on November 14."
                )}
              </p>
              <p class="mt-4 leading-8 text-stone-700">
                {gettext(
                  "Participants gathered at Dorchester Square at 1 p.m., then marched to the U.S. Consulate and the Chinese Consulate."
                )}
              </p>
              <p class="mt-4 leading-8 text-stone-700">
                {gettext(
                  "They called for an international treaty prohibiting the development of artificial superintelligence until there is broad scientific consensus that it can be done safely and controllably, and strong public buy-in."
                )}
              </p>
              <p class="mt-4 leading-8 text-stone-700">
                {gettext(
                  "In its November 16 press release, PauseAI Canada called on Prime Minister Mark Carney to press the leaders of the United States and China for such a treaty at the APEC summit."
                )}
              </p>
              <.link
                id="november-press-release-link"
                href={
                  if @locale == "fr",
                    do: ~p"/fr/manifestation-montreal-2026-11-14/communique",
                    else: ~p"/en/montreal-protest-2026-11-14/press-release"
                }
                class="mt-6 inline-block font-semibold underline decoration-brand decoration-2 underline-offset-4"
              >{gettext("Read the press release")}</.link>
            </div>
          </div>
        </section>
        <section id="toronto-2026-11-14" class="mt-12 scroll-mt-40 border-t border-stone-300 pt-10">
          <h2 class="font-heading text-3xl text-stone-950">
            Toronto ·
            <time datetime="2026-11-14" class="inline-block max-w-full">{gettext("November 14, 2026")}</time>
          </h2>
          <div class="mt-6 grid items-start gap-8 lg:grid-cols-2">
            <div>
              <p class="mt-4 leading-8 text-stone-700">
                {gettext(
                  "Toronto’s AI Treaty March began with speeches at Queen’s Park. Participants marched to the U.S. Consulate and finished at Nathan Phillips Square."
                )}
              </p>
              <p class="mt-4 leading-8 text-stone-700">
                {gettext(
                  "The Montréal and Toronto marches were part of a day of action ahead of the APEC summit."
                )}
              </p>
              <a
                href="https://pauseaitoronto.info/plan#track-record"
                class="mt-5 inline-block font-semibold underline decoration-brand decoration-2 underline-offset-4"
              >{gettext("Toronto’s account of the march")}</a>
            </div>
            <figure>
              <img
                id="toronto-march-photo"
                src={~p"/images/protest-2026-11-14/toronto-crossing.jpg"}
                width="1171"
                height="680"
                loading="lazy"
                decoding="async"
                alt={
                  gettext(
                    "Toronto marchers crossing a downtown street with signs calling for an AI treaty."
                  )
                }
                class="h-auto w-full rounded-xl"
              />
              <figcaption class="mt-2 text-sm text-stone-600">
                <a href="https://pauseaitoronto.info/plan#track-record" class="underline">{gettext(
                  "Photo source: PauseAI Toronto."
                )}</a>
              </figcaption>
            </figure>
          </div>
        </section>
        <section id="montreal-2026-09-26" class="mt-12 scroll-mt-40 border-t border-stone-300 pt-10">
          <h2 class="font-heading text-3xl text-stone-950">
            Montréal ·
            <time datetime="2026-09-26" class="inline-block max-w-full">{gettext("September 26, 2026")}</time>
          </h2>
          <div class="mt-6 grid items-start gap-8 lg:grid-cols-2">
            <figure>
              <img
                src={~p"/images/protest-2026-09-26/clara-lacasse-3-small.webp"}
                width="640"
                height="512"
                loading="lazy"
                decoding="async"
                alt={gettext("Demonstrators holding a PauseAI banner and signs at Phillips Square")}
                class="h-auto w-full rounded-xl"
              />
              <figcaption class="mt-2 text-sm text-stone-600">
                {gettext("At Phillips Square, Montréal. Photo: Clara Lacasse.")}
              </figcaption>
            </figure>
            <div>
              <p class="mt-4 leading-8 text-stone-700">
                {gettext(
                  "Around 40 people gathered at Phillips Square on September 26 for a global, coordinated pause in advanced AI development. The peaceful demonstration ran from 1 to 2 p.m., and organizers distributed around a hundred educational brochures."
                )}
              </p>
              <p class="mt-4 leading-8 text-stone-700">
                {gettext(
                  "PauseAI Canada called on the government to recognize artificial superintelligence as a national security threat, support an international treaty prohibiting its development and coordinate a global pause under democratic control."
                )}
              </p>
              <blockquote class="mt-6 border-l-4 border-brand pl-5 text-lg leading-8 text-stone-800">
                <p>
                  “{gettext(
                    "We need to give ourselves more time to learn how to control AI systems before making them even more powerful. A pause is necessary."
                  )}”
                </p>
                <footer class="mt-3 text-sm font-semibold">
                  {gettext("Jeremy Eliosoff, National Leader, PauseAI Canada")}
                </footer>
              </blockquote>
              <div class="mt-6 flex flex-wrap gap-x-6 gap-y-3 font-semibold">
                <.link
                  id="september-recap-link"
                  href={
                    if @locale == "fr",
                      do: ~p"/fr/manifestation-montreal-2026-09-26",
                      else: ~p"/en/montreal-protest-2026-09-26"
                  }
                  class="underline decoration-brand decoration-2 underline-offset-4"
                >{gettext("Event details and photos")}</.link>
                <.link
                  id="september-press-release-link"
                  href={
                    if @locale == "fr",
                      do: ~p"/fr/manifestation-montreal-2026-09-26/communique",
                      else: ~p"/en/montreal-protest-2026-09-26/press-release"
                  }
                  class="underline decoration-brand decoration-2 underline-offset-4"
                >{gettext("Read the press release")}</.link>
                <a
                  href="https://www.ledevoir.com/actualites/societe/1012274/montrealais-demandent-deceleration-developpement-ia"
                  class="underline decoration-brand decoration-2 underline-offset-4"
                >{gettext("Read the report in Le Devoir (French)")}</a>
              </div>
            </div>
          </div>
        </section>
        <div class="mt-12 border-t border-stone-300 pt-8">
          <.link
            href={
              if @locale == "fr",
                do: ~p"/fr/participer?intent=action",
                else: ~p"/en/participate?intent=action"
            }
            class="inline-flex min-h-11 items-center whitespace-nowrap rounded-full bg-brand px-5 py-3 font-semibold text-stone-950 hover:bg-brand-strong"
          >{gettext("Take action")}</.link>
        </div>
      </article>
    </Layouts.app>
    """
  end
end
