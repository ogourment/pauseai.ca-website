defmodule PauseAiCaWeb.LibraryLive do
  @moduledoc """
  The bilingual reading library and the Canadian voices behind it.

  Everything is available to everyone; the stages order the material, they do
  not gate it. Cards say plainly when the linked source is only available in the
  other language, so a French reader is never sent to an English page without
  warning.
  """

  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Library
  alias PauseAiCa.Library.Reference
  alias PauseAiCa.Library.Resource
  alias PauseAiCa.Library.Signatory
  alias PauseAiCa.Library.Voice

  @impl true
  def mount(_params, _session, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     socket
     |> assign(:locale, locale)
     |> assign(:page_title, page_title(locale))
     |> assign(:stages, Library.stages())
     |> assign(:voices, Library.voices(locale))
     |> assign(:signatories, Library.signatories())
     |> assign(
       :participation_context,
       PauseAiCa.Accounts.Onboarding.context(
         %{"locale" => locale, "from" => "home_footer"},
         socket.assigns[:learning_visitor_id]
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
      translated_path={if(@locale == "fr", do: ~p"/en/learn", else: ~p"/fr/comprendre")}
    >
      <section class="mx-auto max-w-5xl px-5 pt-14 pb-8">
        <h1 class="max-w-3xl font-heading text-5xl leading-[1.05] text-stone-950 sm:text-6xl">
          {page_title(@locale)}
        </h1>
        <p class="mt-6 max-w-3xl text-xl leading-9 text-stone-700">{lede(@locale)}</p>
        <.link
          id="learn-self-assessment"
          navigate={if(@locale == "fr", do: ~p"/fr#questions", else: ~p"/en#questions")}
          class="mt-5 inline-flex font-semibold underline decoration-brand decoration-2 underline-offset-4"
        >
          {gettext("Where do I stand?")}
        </.link>
      </section>

      <PauseAiCaWeb.LearningJourney.journey locale={@locale} current_scope={@current_scope} />
      <section id="voices" class="border-y border-stone-200 bg-white">
        <div class="mx-auto max-w-5xl px-5 py-14">
          <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
            {voices_heading(@locale)}
          </h2>
          <p class="mt-3 max-w-3xl leading-7 text-stone-600">{voices_note(@locale)}</p>

          <ul class="mt-8 grid gap-6 lg:grid-cols-2">
            <li
              :for={voice <- @voices}
              id={"voice-#{voice.id}"}
              class="topic-voices flex flex-col rounded-2xl border border-stone-200 p-6"
            >
              <span class="learning-topic topic-voices self-start">{gettext("People and quotations")}</span>
              <h3 class="mt-3 font-heading text-2xl text-stone-950">{voice.name}</h3>
              <p class="mt-1 text-sm leading-6 text-stone-500">
                {Voice.affiliation(voice, @locale)}
              </p>

              <blockquote
                :for={quotation <- voice_quotes(voice, @locale)}
                class="mt-5 border-l-4 border-brand pl-4"
              >
                <p class="leading-7 text-stone-800">
                  “{Voice.quote_text(quotation, @locale)}”
                </p>
                <footer class="mt-2 text-sm text-stone-500">
                  <a
                    href={quotation.url}
                    rel="noreferrer"
                    class="underline decoration-brand decoration-2 underline-offset-4"
                  >{publisher_name(quotation.source)}</a><span :if={quotation.said_on}>, {quotation.said_on}</span><span
                    :if={quotation.language != @locale}
                    class="ml-2 rounded border border-stone-300 px-1.5 py-0.5 text-xs uppercase"
                  >{quotation.language}</span>
                </footer>
              </blockquote>

              <div class="mt-5 border-t border-stone-200 pt-4">
                <p class="text-xs font-bold uppercase tracking-[0.14em] text-stone-500">
                  {further_label(@locale)}
                </p>
                <ul class="mt-2 space-y-1.5">
                  <li :for={reference <- voice.references} class="leading-6">
                    <a
                      href={reference.url}
                      rel="noreferrer"
                      class="text-stone-900 underline decoration-brand decoration-2 underline-offset-4"
                    >{Reference.label(reference, @locale)}</a>
                    <span class="text-sm text-stone-500">· {publisher_name(reference.publisher)}</span>
                  </li>
                </ul>
              </div>
            </li>
          </ul>
        </div>
      </section>

      <section id="parliament" class="mx-auto max-w-5xl px-5 py-14">
        <span class="learning-topic topic-politics">{gettext("Politics")}</span>
        <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
          {parliament_heading(@locale)}
        </h2>
        <p class="mt-3 max-w-3xl leading-7 text-stone-600">{parliament_note(@locale)}</p>

        <div class="mt-8 grid gap-8 md:grid-cols-2">
          <div :for={chamber <- [:commons, :senate]}>
            <h3 class="font-heading text-xl text-brand-ink">{chamber_label(chamber, @locale)}</h3>
            <ul class="mt-3 space-y-2">
              <li
                :for={signatory <- Enum.filter(@signatories, &(&1.chamber == chamber))}
                class="leading-6"
              >
                <span class="font-semibold text-stone-900">{signatory.name}</span>
                <span class="text-sm text-stone-500">· {Signatory.party(signatory, @locale)}</span>
                <span :if={Signatory.note(signatory, @locale)} class="block text-sm text-stone-500">
                  {Signatory.note(signatory, @locale)}
                </span>
              </li>
            </ul>
          </div>
        </div>

        <p class="mt-6">
          <a
            id="parliament-source"
            href={Library.statement_url(@locale)}
            rel="noreferrer"
            class="font-semibold text-stone-900 underline decoration-brand decoration-2 underline-offset-4"
          >
            {parliament_source(@locale)} <span aria-hidden="true">↗</span>
          </a>
        </p>
      </section>

      <section id="reading" class="mx-auto max-w-5xl px-5 py-14">
        <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
          {reading_heading(@locale)}
        </h2>

        <div :for={stage <- @stages} id={"stage-#{stage}"} class="mt-10">
          <h3 class="font-heading text-2xl text-brand-ink">
            {Library.stage_label(stage, @locale)}
          </h3>

          <ul class="mt-4 grid gap-5 md:grid-cols-2">
            <li
              :for={resource <- Library.resources(stage) |> Enum.sort_by(&(&1.language != @locale))}
              id={"resource-#{resource.id}"}
              class="relative flex flex-col rounded-2xl border border-stone-200 bg-white p-6 transition hover:shadow-md"
            >
              <h4 class="pr-10 font-heading text-xl leading-snug text-stone-950">
                {Resource.copy(resource, @locale).title}
              </h4>
              <p class="mt-3 leading-7 text-stone-600">
                {Resource.copy(resource, @locale).summary}
              </p>
              <p class="mt-4 flex flex-wrap items-center gap-2 text-sm text-stone-500">
                <span>{publisher_name(resource.publisher)}</span>
                <span :if={resource.author}>· {author_label(resource.author)}</span>
                <span
                  :if={resource.canadian}
                  class="rounded border border-brand px-1.5 py-0.5 text-xs font-semibold uppercase text-brand-ink"
                >
                  {canadian_label(@locale)}
                </span>
                <span
                  :if={Resource.foreign_language?(resource, @locale)}
                  class="rounded border border-stone-300 px-1.5 py-0.5 text-xs uppercase"
                >
                  {resource.language}
                </span>
              </p>
              <a
                href={~p"/learning/resources/#{resource.id}"}
                target="_blank"
                rel="noreferrer"
                class="mt-4 inline-flex font-semibold text-stone-900 underline decoration-brand decoration-2 underline-offset-4"
              >
                {read_label(@locale)} <span aria-hidden="true">↗</span>
              </a>
              <.resource_bookmark
                title={Resource.copy(resource, @locale).title}
                current_scope={@current_scope}
                selected={!!@current_scope && resource.id in @current_scope.user.saved_resources}
                href={
                  if @current_scope,
                    do: ~p"/bookmarks/#{resource.id}?locale=#{@locale}",
                    else: ~p"/users/register?#{%{bookmark: resource.id, locale: @locale}}"
                }
                method={if @current_scope, do: "post", else: "get"}
              />
            </li>
          </ul>
        </div>
      </section>

      <section id="updates" class="border-t border-stone-200 bg-white">
        <div id="local-participation" class="mx-auto max-w-5xl px-5 py-12">
          <.live_component
            module={PauseAiCaWeb.ParticipationForm}
            id="participation-entry"
            locale={@locale}
            current_scope={@current_scope}
            intent="newsletter"
            city=""
            registration={false}
            context={@participation_context}
          />
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp page_title(_locale), do: gettext("Should we slow AI down?")

  defp voice_quotes(voice, locale) do
    local = Enum.filter(voice.quotes, &(&1.language == locale))
    if local == [], do: voice.quotes, else: local
  end

  defp lede(_locale),
    do:
      gettext(
        "Researchers in Canada and elsewhere warn that advanced AI could escape human control. Read their arguments and the proposals for responding to that risk."
      )

  defp voices_heading(_locale), do: gettext("Canadian voices")

  defp voices_note(_locale),
    do:
      gettext(
        "Two of the three Turing Award winners for deep learning built their careers in Canada. Both now say the technology they created could escape human control."
      )

  defp parliament_heading(_locale), do: gettext("Parliamentarians have already signed")

  defp parliament_note(_locale),
    do:
      gettext(
        "Current and former Canadian parliamentarians from several parties have signed a statement calling for an international agreement to prohibit superintelligent AI. Read the statement and see who has signed."
      )

  defp author_label("Chaired by Yoshua Bengio"), do: gettext("Chaired by Yoshua Bengio")
  defp author_label("Founded by Yoshua Bengio"), do: gettext("Founded by Yoshua Bengio")
  defp author_label(author), do: author

  defp chamber_label(:commons, _locale), do: gettext("House of Commons")
  defp chamber_label(:senate, _locale), do: gettext("Senate")

  defp parliament_source(_locale), do: gettext("The statement and the full list of supporters")

  defp reading_heading(_locale), do: gettext("The arguments")

  defp further_label(_locale), do: gettext("Further reading")

  defp canadian_label(_locale), do: gettext("Canada")

  defp read_label(_locale), do: gettext("Read it")
end
