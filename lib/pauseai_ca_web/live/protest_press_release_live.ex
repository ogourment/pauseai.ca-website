defmodule PauseAiCaWeb.ProtestPressReleaseLive do
  use PauseAiCaWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title:
         gettext("PauseAI Canada calls for international action after Montréal demonstration")
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
          do: ~p"/en/montreal-protest-2026-09-26/press-release",
          else: ~p"/fr/manifestation-montreal-2026-09-26/communique"
      }
    >
      <article id="protest-press-release-page" class="mx-auto max-w-4xl px-5 py-14">
        <p class="font-heading text-sm uppercase tracking-[0.18em] text-stone-600">
          {gettext("Press release · September 26, 2026")}
        </p>
        <h1 class="mt-5 font-heading text-5xl leading-[1.04] text-stone-950 sm:text-6xl">
          {gettext("PauseAI Canada calls for international action after Montréal demonstration")}
        </h1>
        <p class="mt-8 text-xl leading-9 text-stone-800">
          {gettext(
            "MONTRÉAL, September 26, 2026 — PauseAI Canada organized a demonstration attended by around 40 people. We call on the Canadian government to recognize the development of artificial superintelligence as a national security threat and support an international treaty banning its development."
          )}
        </p>
        <section id="canada-policy-update" class="mt-10 border-l-4 border-brand bg-brand-wash p-6">
          <h2 class="font-heading text-2xl text-stone-950">
            {gettext("Canada's next step")}
          </h2>
          <p class="mt-3 leading-8 text-stone-800">
            {gettext(
              "Prime Minister Mark Carney joined other leaders in calling for stronger oversight of frontier AI models, including independent evaluations, coordinated standards and consideration of an international institution. We welcome this step."
            )}
          </p>
          <p class="mt-3 leading-8 text-stone-800">
            {gettext(
              "We now ask him to go further and join the more than 30 Canadian MPs and senators whom ControlAI says support recognizing superintelligent AI as a national security threat and negotiating an international prohibition on its development."
            )}
          </p>
          <div class="mt-4 flex flex-wrap gap-x-6 gap-y-2 text-sm font-semibold">
            <a
              href="https://www.regjeringen.no/contentassets/35b2ea6933304966bd739ff4b8107300/a-call-for-control-of-frontier-ai-models-final.pdf"
              rel="noreferrer"
              class="underline decoration-brand decoration-2 underline-offset-4"
            >{gettext("Read the leaders' call (PDF)")}</a>
            <a
              href="https://controlai.org/canada-statement/en"
              rel="noreferrer"
              class="underline decoration-brand decoration-2 underline-offset-4"
            >{gettext("Read ControlAI's Canada statement")}</a>
          </div>
        </section>
        <div class="mt-10 space-y-6 leading-8 text-stone-800">
          <p>
            {gettext(
              "Recent reported incidents show AI agents attempting unauthorized access to government and company websites and coordinating through online forums. These incidents strengthen the case for slowing the development of increasingly capable systems while safety and control remain unresolved."
            )}
          </p>
          <p>
            {gettext(
              "A pause needs an international agreement so that countries and developers follow the same rules. We ask Canada to help negotiate that agreement."
            )}
          </p>
        </div>
        <div class="mt-8 text-sm leading-6 text-stone-600">
          <p>{gettext("Background on the reported incidents:")}</p>
          <ul class="mt-2 list-disc space-y-1 pl-5">
            <li>
              <a
                href="https://www.pm.gov.au/media/press-conference-new-york"
                rel="noreferrer"
                class="underline decoration-brand decoration-2 underline-offset-4"
              >
                {gettext("Australian Prime Minister, September 24, 2026")}
              </a>
            </li>
            <li>
              <a
                href="https://transluce.org/agent-activity"
                rel="noreferrer"
                class="underline decoration-brand decoration-2 underline-offset-4"
              >
                {gettext("Transluce incident research, September 2026")}
              </a>
            </li>
          </ul>
        </div>
        <figure class="mt-12 grid items-start gap-6 border-l-4 border-brand bg-brand-wash p-6 sm:grid-cols-[1fr_9rem]">
          <blockquote class="text-xl leading-8 text-stone-900">
            <p>
              “{gettext(
                "AIs are starting to do increasingly sophisticated things that we didn’t ask for, aren’t aware of, and can’t restrain with technical or legal measures - even before they are released to the public.  We are starting to lose control.  We are not anti-AI, but we want to pause the training of frontier models so we can learn how to manage AI systems before they get any more powerful."
              )}”
            </p>
            <footer class="mt-5 text-base font-semibold">
              {gettext("Jeremy Eliosoff, National Leader, PauseAI Canada")}
            </footer>
          </blockquote>
          <div>
            <picture>
              <source
                type="image/webp"
                srcset={"#{~p"/images/protest-2026-09-26/clara-lacasse-14-small.webp"} 512w, #{~p"/images/protest-2026-09-26/clara-lacasse-14.webp"} 960w"}
                sizes="(min-width: 768px) 400px, calc(100vw - 40px)"
              />
              <img
                src={~p"/images/protest-2026-09-26/clara-lacasse-14.jpg"}
                width="960"
                height="1200"
                alt={gettext("Jeremy Eliosoff at the Montréal protest")}
                class="h-auto w-full rounded-lg"
              />
            </picture>
            <figcaption class="mt-2 text-xs text-stone-600">
              {gettext("Photo: Clara Lacasse.")}
            </figcaption>
          </div>
        </figure>
        <section class="mt-12 border-t border-stone-200 pt-8">
          <h2 class="font-heading text-2xl">{gettext("About PauseAI Canada")}</h2>
          <p class="mt-3 leading-8 text-stone-700">
            {gettext(
              "The Canadian branch of the international PauseAI movement, PauseAI Canada is a citizens’ group campaigning for an international treaty to pause the development of frontier artificial intelligence until it can be done safely."
            )}
          </p>
          <p class="mt-5">
            {gettext("Media inquiries")}:
            <a href="mailto:info@pauseai.ca" class="underline">info@pauseai.ca</a>
          </p>
          <.link
            navigate={
              if @locale == "fr",
                do: ~p"/fr/manifestation-montreal-2026-09-26",
                else: ~p"/en/montreal-protest-2026-09-26"
            }
            class="mt-8 inline-block font-semibold underline decoration-brand decoration-2 underline-offset-4"
          >
            {gettext("See the protest recap and photos")}
          </.link>
        </section>
      </article>
    </Layouts.app>
    """
  end
end
