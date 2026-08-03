defmodule PauseAiCaWeb.LibraryLive do
  @moduledoc """
  The bilingual reading library and the Canadian voices behind it.

  Everything is available to everyone; the stages order the material, they do
  not gate it. Cards say plainly when the linked source is only available in the
  other language, so a French reader is never sent to an English page without
  warning.
  """

  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Campaigns.Subscription
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
     |> assign(:voices, Library.voices())
     |> assign(:signatories, Library.signatories())
     |> assign(:subscribe_form, to_form(%{"email" => "", "consent" => "false"}, as: :subscribe))
     |> assign(:subscribe_state, :idle)}
  end

  @impl true
  def handle_event("update-subscribe", %{"subscribe" => params}, socket) do
    {:noreply, assign(socket, :subscribe_form, to_form(subscribe_params(params), as: :subscribe))}
  end

  def handle_event("subscribe", %{"subscribe" => params}, socket) do
    params = subscribe_params(params)
    socket = assign(socket, :subscribe_form, to_form(params, as: :subscribe))

    if params["consent"] == "true" do
      case Subscription.subscribe(params["email"], socket.assigns.locale) do
        {:ok, _status} -> {:noreply, assign(socket, :subscribe_state, :subscribed)}
        {:error, reason} -> {:noreply, assign(socket, :subscribe_state, {:error, reason})}
      end
    else
      {:noreply, assign(socket, :subscribe_state, {:error, :consent_required})}
    end
  end

  defp subscribe_params(params) do
    %{
      "email" => params["email"] || "",
      "consent" => if(params["consent"] in ["true", "on"], do: "true", else: "false")
    }
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
      </section>

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
              class="flex flex-col rounded-2xl border border-stone-200 p-6"
            >
              <h3 class="font-heading text-2xl text-stone-950">{voice.name}</h3>
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
                  >{quotation.source}</a><span :if={quotation.said_on}>, {quotation.said_on}</span><span
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
                    <span class="text-sm text-stone-500">· {reference.publisher}</span>
                  </li>
                </ul>
              </div>
            </li>
          </ul>
        </div>
      </section>

      <section id="parliament" class="mx-auto max-w-5xl px-5 py-14">
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
              :for={resource <- Library.resources(stage)}
              id={"resource-#{resource.id}"}
              class="flex flex-col rounded-2xl border border-stone-200 bg-white p-6 transition hover:shadow-md"
            >
              <h4 class="font-heading text-xl leading-snug text-stone-950">
                {Resource.copy(resource, @locale).title}
              </h4>
              <p class="mt-3 leading-7 text-stone-600">
                {Resource.copy(resource, @locale).summary}
              </p>
              <p class="mt-4 flex flex-wrap items-center gap-2 text-sm text-stone-500">
                <span>{resource.publisher}</span>
                <span :if={resource.author}>· {resource.author}</span>
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
                href={resource.url}
                rel="noreferrer"
                class="mt-4 inline-flex font-semibold text-stone-900 underline decoration-brand decoration-2 underline-offset-4"
              >
                {read_label(@locale)} <span aria-hidden="true">↗</span>
              </a>
            </li>
          </ul>
        </div>
      </section>

      <section id="updates" class="border-t border-stone-200 bg-white">
        <div class="mx-auto max-w-3xl px-5 py-14">
          <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
            {updates_heading(@locale)}
          </h2>
          <p class="mt-3 leading-7 text-stone-600">{updates_note(@locale)}</p>

          <.form
            for={@subscribe_form}
            id="subscribe-form"
            phx-change="update-subscribe"
            phx-submit="subscribe"
            class="mt-6"
          >
            <.input
              field={@subscribe_form[:email]}
              type="email"
              label={email_label(@locale)}
              autocomplete="email"
            />
            <label class="mt-2 flex items-start gap-3">
              <input type="hidden" name="subscribe[consent]" value="false" />
              <input
                type="checkbox"
                id="subscribe-consent"
                name="subscribe[consent]"
                value="true"
                checked={@subscribe_form[:consent].value == "true"}
                class="mt-1 size-4 shrink-0"
              />
              <span class="text-sm leading-6 text-stone-700">{consent_label(@locale)}</span>
            </label>

            <button
              type="submit"
              id="subscribe"
              phx-disable-with={subscribing_label(@locale)}
              class="mt-5 rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 transition hover:-translate-y-0.5 hover:bg-brand-strong"
            >
              {subscribe_cta(@locale)}
            </button>
          </.form>

          <p
            :if={@subscribe_state == :subscribed}
            id="subscribe-success"
            role="status"
            class="mt-5 font-semibold text-green-800"
          >
            {subscribed_message(@locale)}
          </p>
          <p
            :if={match?({:error, _reason}, @subscribe_state)}
            id="subscribe-error"
            role="alert"
            class="mt-5 font-semibold text-red-700"
          >
            {subscribe_error_message(@subscribe_state, @locale)}
          </p>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp page_title("fr"), do: "Faut-il ralentir l'IA?"
  defp page_title(_locale), do: "Should we slow AI down?"

  defp voice_quotes(voice, locale) do
    local = Enum.filter(voice.quotes, &(&1.language == locale))
    if local == [], do: voice.quotes, else: local
  end

  defp lede("fr"),
    do:
      "Les gens qui ont construit cette technologie sont parmi les plus inquiets de ce qu'elle devient, et plusieurs d'entre eux travaillent ici. Voici ce qu'ils disent, et les arguments — pour et contre — que vous pouvez examiner vous-même."

  defp lede(_locale),
    do:
      "The people who built this technology are among the most worried about where it is going, and several of them work here. Here is what they say, and the arguments — for and against — you can weigh yourself."

  defp voices_heading("fr"), do: "Des voix canadiennes"
  defp voices_heading(_locale), do: "Canadian voices"

  defp voices_note("fr"),
    do:
      "Deux des trois lauréats du prix Turing pour l'apprentissage profond ont bâti leur carrière au Canada. Tous deux affirment aujourd'hui que la technologie qu'ils ont créée pourrait échapper au contrôle humain."

  defp voices_note(_locale),
    do:
      "Two of the three Turing Award winners for deep learning built their careers in Canada. Both now say the technology they created could escape human control."

  defp parliament_heading("fr"), do: "Des parlementaires l'ont déjà signé"
  defp parliament_heading(_locale), do: "Parliamentarians have already signed"

  defp parliament_note("fr"),
    do:
      "Seize député·es et sénateur·rices, de tous les partis et des deux chambres, ont signé la déclaration réclamant un accord international pour interdire l'IA superintelligente. Écrire à votre député·e n'est pas un geste marginal: la question est déjà à Ottawa."

  defp parliament_note(_locale),
    do:
      "Sixteen MPs and Senators, from every party and both chambers, have signed the statement calling for an international agreement to prohibit superintelligent AI. Writing to your MP is not a fringe act: the question is already in Ottawa."

  defp chamber_label(:commons, "fr"), do: "Chambre des communes"
  defp chamber_label(:commons, _locale), do: "House of Commons"
  defp chamber_label(:senate, "fr"), do: "Sénat"
  defp chamber_label(:senate, _locale), do: "Senate"

  defp parliament_source("fr"), do: "La déclaration et la liste complète des appuis"
  defp parliament_source(_locale), do: "The statement and the full list of supporters"

  defp reading_heading("fr"), do: "Les arguments"
  defp reading_heading(_locale), do: "The arguments"

  defp further_label("fr"), do: "Pour aller plus loin"
  defp further_label(_locale), do: "Further reading"

  defp canadian_label("fr"), do: "Canada"
  defp canadian_label(_locale), do: "Canada"

  defp read_label("fr"), do: "Lire"
  defp read_label(_locale), do: "Read it"

  defp updates_heading("fr"), do: "Recevoir les mises à jour"
  defp updates_heading(_locale), do: "Get updates"

  defp updates_note("fr"),
    do:
      "Quelques courriels par mois de PauseAI Canada: ce qui bouge au fédéral, les mobilisations, et les moments où votre voix compte le plus. Désabonnement en un clic."

  defp updates_note(_locale),
    do:
      "A few emails a month from PauseAI Canada: what is moving federally, mobilisations, and the moments when your voice counts most. One-click unsubscribe."

  defp email_label("fr"), do: "Votre courriel"
  defp email_label(_locale), do: "Your email"

  defp consent_label("fr"),
    do:
      "J'accepte de recevoir les courriels de PauseAI Canada. Mon adresse est conservée chez Brevo, notre fournisseur d'envoi, et n'est jamais vendue ni partagée."

  defp consent_label(_locale),
    do:
      "I agree to receive emails from PauseAI Canada. My address is held by Brevo, our sending provider, and is never sold or shared."

  defp subscribe_cta("fr"), do: "M'inscrire"
  defp subscribe_cta(_locale), do: "Sign me up"

  defp subscribing_label("fr"), do: "Inscription…"
  defp subscribing_label(_locale), do: "Signing up…"

  defp subscribed_message("fr"), do: "C'est fait. Merci — vous recevrez le prochain envoi."
  defp subscribed_message(_locale), do: "Done. Thank you — you will get the next mailing."

  defp subscribe_error_message({:error, :consent_required}, "fr"),
    do: "Cochez la case de consentement avant de vous inscrire."

  defp subscribe_error_message({:error, :consent_required}, _locale),
    do: "Please tick the consent box before signing up."

  defp subscribe_error_message({:error, :invalid_email}, "fr"),
    do: "Ce courriel ne semble pas valide."

  defp subscribe_error_message({:error, :invalid_email}, _locale),
    do: "That email does not look valid."

  defp subscribe_error_message({:error, :not_configured}, "fr"),
    do: "L'infolettre n'est pas encore branchée sur cet environnement."

  defp subscribe_error_message({:error, :not_configured}, _locale),
    do: "The mailing list is not connected in this environment yet."

  defp subscribe_error_message(_state, "fr"),
    do: "L'inscription a échoué. Réessayez dans un moment."

  defp subscribe_error_message(_state, _locale), do: "Sign-up failed. Please try again shortly."
end
