defmodule PauseAiCaWeb.NovemberPressReleaseLive do
  use PauseAiCaWeb, :live_view

  @impl true
  def mount(_, _, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title:
         gettext(
           "March in Montreal: PauseAI Canada Urges Mark Carney to Demand an International Treaty Banning Superintelligence at the APEC Summit"
         )
     )}
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
      translated_path={
        if @locale == "fr",
          do: ~p"/en/montreal-protest-2026-11-14/press-release",
          else: ~p"/fr/manifestation-montreal-2026-11-14/communique"
      }
    >
      <article id="november-press-release" class="mx-auto max-w-4xl px-3 py-12 sm:px-5 sm:py-16">
        <p class="text-sm font-semibold uppercase tracking-wide text-stone-600">
          {gettext("Press release · November 16, 2026")}
        </p>
        <h1 class="mt-5 font-heading text-3xl leading-tight text-stone-950 [overflow-wrap:anywhere] sm:text-5xl">
          {gettext(
            "March in Montreal: PauseAI Canada Urges Mark Carney to Demand an International Treaty Banning Superintelligence at the APEC Summit"
          )}
        </h1>
        <p class="mt-7 font-semibold">{gettext("MONTREAL, November 16, 2026")}</p>
        <div class="mt-6 space-y-6">
          <p class="mt-4 leading-8 text-stone-700">
            {gettext(
              "Last Saturday, November 14, PauseAI Canada joined a demonstration in Montreal organized by the Coalition for an AI Treaty, which brings together PauseAI Canada, Stop the AI Race, and Horizon Omega."
            )}
          </p>
          <p class="mt-4 leading-8 text-stone-700">
            {gettext(
              "Around fifty participants gathered at 1:00 PM at Dorchester Square before marching to the U.S. Consulate and then to the Chinese Consulate, demanding an international treaty banning the development of artificial superintelligence, not lifted before there is broad scientific consensus that it will be done safely and controllably, and strong public buy-in"
            )}
          </p>
          <p class="mt-4 leading-8 text-stone-700">
            {gettext(
              "Defined as AI surpassing human capabilities across most cognitive tasks, superintelligence is the stated goal of frontier AI companies, including OpenAI and Anthropic, despite warnings from experts such as Yoshua Bengio and Geoffrey Hinton that developing it without reliable control and alignment methods would pose an existential threat to humanity."
            )}
          </p>
          <p class="mt-4 leading-8 text-stone-700">
            {gettext(
              "Over the past few months, a series of cybersecurity incidents have involved AI agents that, acting against the wishes of their creators, committed illegal acts, hacked government and corporate websites, and coordinated covertly. These events demonstrate that labs are unable to control even their current models. We therefore believe it is urgent to halt the race to develop ever more powerful AI, and that international coordination is required to do so."
            )}
          </p>
          <p class="mt-4 leading-8 text-stone-700">
            {gettext(
              "Alongside the Montreal march, demonstrations took place on Saturday in Toronto, Vancouver, Washington, D.C., San Francisco, New York, Boston, Paris, Marseille, and Berlin. These citizen mobilizations were part of a global day of action ahead of the APEC Summit in Shenzhen on November 18 and 19, where world leaders will gather, and which represents a key opportunity to begin negotiating an international AI treaty."
            )}
          </p>
          <p class="mt-4 leading-8 text-stone-700">
            {gettext(
              "PauseAI Canada calls on Prime Minister Mark Carney to commit to pressuring the leaders of the United States and China at the summit to establish such a treaty. Given the existential risks posed by superintelligence, negotiating an international treaty banning its development must be treated as a top priority for Canada's national security."
            )}
          </p>
        </div>
        <blockquote class="mt-8 border-l-4 border-brand pl-5 text-lg leading-8 text-stone-800">
          <p>
            {gettext(
              "“People are starting to recognize the threat. In the past few months, \"AI takeover\" and \"human extinction\" have entered the mainstream discourse, alongside calls for a global AI pause. And actionable paths to a pause are starting to take shape. AI hardware can be replaced to lock in current capabilities. There are roadmaps for collaboration even among adversarial nations. Anyone listening to this can talk to their political representative about AI risks, and get in touch with PauseAI, ControlAI, Stop the AI Race, or any number of the proliferating groups dedicated to AI safety. This crisis concerns us all, and everyone can do their part to ensure humanity remains in control of its destiny.”"
            )}
          </p>
          <footer class="mt-4 text-base font-semibold">
            {gettext("Jeremy Eliosoff, Founder and National Leader, PauseAI Canada")}
          </footer>
        </blockquote>
        <section class="mt-10 border-t border-stone-300 pt-7">
          <h2 class="font-heading text-2xl">{gettext("About PauseAI Canada")}</h2>
          <p class="mt-4 leading-8 text-stone-700">
            {gettext(
              "The national branch of the international PauseAI movement, PauseAI Canada is a citizens' group campaigning for an international treaty that would pause the development of frontier artificial intelligence until it can be done safely."
            )}
          </p>
        </section>
        <section class="mt-8">
          <h2 class="font-heading text-2xl">{gettext("Media Contact")}</h2>
          <p class="mt-4 leading-7">
            Manolis Daris-Bécotte<br />{gettext("Volunteer, PauseAI Canada")}<br />
            <a href="tel:+15142143250" class="underline">514 214 3250</a><br />
            <a href="mailto:manolisdarisbecotte@pauseai.info" class="break-all underline">manolisdarisbecotte@pauseai.info</a>
          </p>
        </section>
        <div class="mt-8 flex flex-wrap gap-x-6 gap-y-3 font-semibold">
          <.link
            id="november-actions-return"
            href={
              if @locale == "fr",
                do: ~p"/fr/nos-actions#montreal-2026-11-14",
                else: ~p"/en/our-actions#montreal-2026-11-14"
            }
            class="underline decoration-brand decoration-2 underline-offset-4"
          >{gettext("Our actions and photos")}</.link>
          <a
            href="https://drive.google.com/drive/folders/1slbLd1MK7VrmGv4iDeBUdCCuKZ4SGKW7"
            class="underline decoration-brand decoration-2 underline-offset-4"
          >{gettext("Press photos · Clara Lacasse")}</a>
        </div>
      </article>
    </Layouts.app>
    """
  end
end
