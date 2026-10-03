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
     |> assign(:voices, Library.voices(locale))
     |> assign(:signatories, Library.signatories())
     |> assign(
       :subscribe_form,
       to_form(%{"email" => "", "postal_code" => "", "city" => "", "consent" => "false"},
         as: :subscribe
       )
     )
     |> assign(:subscribe_state, :idle)
     |> assign(
       :local_form,
       to_form(
         PauseAiCa.Accounts.change_user_local_context(
           if(socket.assigns.current_scope,
             do: socket.assigns.current_scope.user,
             else: %PauseAiCa.Accounts.User{}
           )
         ),
         as: :local
       )
     )
     |> assign(:local_saved, false)
     |> assign(:local_ready, false)
     |> assign(:local_groups, [])}
  end

  @impl true
  def handle_event("update-subscribe", %{"subscribe" => params}, socket) do
    {:noreply, assign(socket, :subscribe_form, to_form(subscribe_params(params), as: :subscribe))}
  end

  def handle_event("subscribe", %{"subscribe" => params}, socket) do
    params = subscribe_params(params)
    socket = assign(socket, :subscribe_form, to_form(params, as: :subscribe))

    if params["consent"] == "true" do
      case Subscription.subscribe(params["email"], socket.assigns.locale, params) do
        {:ok, _status} -> {:noreply, assign(socket, :subscribe_state, :subscribed)}
        {:error, reason} -> {:noreply, assign(socket, :subscribe_state, {:error, reason})}
      end
    else
      {:noreply, assign(socket, :subscribe_state, {:error, :consent_required})}
    end
  end

  def handle_event("validate-local", %{"local" => params}, socket) do
    user =
      if socket.assigns.current_scope,
        do: socket.assigns.current_scope.user,
        else: %PauseAiCa.Accounts.User{}

    changeset = PauseAiCa.Accounts.change_user_local_context(user, params)

    {:noreply,
     assign(socket,
       local_form: to_form(%{changeset | action: :validate}, as: :local),
       local_ready: false,
       local_saved: false
     )}
  end

  def handle_event("save-local", %{"local" => params}, socket) do
    user =
      if socket.assigns.current_scope,
        do: socket.assigns.current_scope.user,
        else: %PauseAiCa.Accounts.User{}

    changeset = PauseAiCa.Accounts.change_user_local_context(user, params)

    if changeset.valid? do
      result =
        if socket.assigns.current_scope,
          do: PauseAiCa.Accounts.update_user_local_context(user, params),
          else: {:ok, Ecto.Changeset.apply_changes(changeset)}

      case result do
        {:ok, _} ->
          {:noreply,
           assign(socket,
             local_ready: true,
             local_groups:
               PauseAiCa.LocalGroups.for_fsa(Ecto.Changeset.get_field(changeset, :fsa)),
             local_saved: !!socket.assigns.current_scope,
             local_form: to_form(changeset, as: :local)
           )}

        {:error, changeset} ->
          {:noreply, assign(socket, :local_form, to_form(changeset, as: :local))}
      end
    else
      {:noreply, assign(socket, :local_form, to_form(%{changeset | action: :insert}, as: :local))}
    end
  end

  defp subscribe_params(params) do
    %{
      "email" => params["email"] || "",
      "postal_code" => params["postal_code"] || "",
      "city" => params["city"] || "",
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
              class="learning-card topic-voices flex flex-col rounded-2xl border border-stone-200 p-6"
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
              <.link
                href={
                  if @current_scope,
                    do: ~p"/bookmarks/#{resource.id}?locale=#{@locale}",
                    else: ~p"/users/register?#{%{bookmark: resource.id, locale: @locale}}"
                }
                method={if @current_scope, do: "post", else: "get"}
                aria-label={
                  gettext("%{action}: %{title}",
                    action:
                      if(@current_scope && resource.id in @current_scope.user.saved_resources,
                        do: gettext("Saved"),
                        else: bookmark_label(@locale)
                      ),
                    title: Resource.copy(resource, @locale).title
                  )
                }
                class="group absolute right-3 top-3 inline-flex size-11 items-center justify-center rounded-full text-stone-700 hover:bg-brand-wash focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand"
              >
                <.icon
                  name={
                    if @current_scope && resource.id in @current_scope.user.saved_resources,
                      do: "hero-bookmark-solid",
                      else: "hero-bookmark"
                  }
                  class="size-5"
                />
                <span class="pointer-events-none absolute right-0 top-full z-10 w-max max-w-56 rounded bg-stone-900 px-2 py-1 text-sm text-white opacity-0 group-hover:opacity-100 group-focus-visible:opacity-100">
                  {if @current_scope && resource.id in @current_scope.user.saved_resources,
                    do: gettext("Saved"),
                    else: bookmark_label(@locale)}
                </span>
              </.link>
            </li>
          </ul>
        </div>
      </section>

      <section id="local-participation" class="mx-auto max-w-5xl px-5 py-14">
        <h2 class="font-heading text-3xl">{gettext("Join or start a group")}</h2>
        <p class="mt-3 leading-7">
          {gettext(
            "Enter the first three characters of your postal code when you want local invitations. You can also read the organizing guide or attend an event."
          )}
        </p>
        <.form
          for={@local_form}
          id="local-interest-form"
          phx-change="validate-local"
          phx-submit="save-local"
          class="mt-5 max-w-lg"
        >
          <.input
            field={@local_form[:fsa]}
            label={gettext("Postal area (FSA)")}
            placeholder="H2X"
            autocomplete="postal-code"
            required
            maxlength="3"
          />
          <.input
            :if={@current_scope}
            field={@local_form[:local_updates]}
            type="checkbox"
            label={gettext("I would like invitations to local activities.")}
          />
          <button class="mt-3 rounded-full bg-brand px-5 py-3 font-bold" type="submit">{gettext(
            "Continue locally"
          )}</button>
        </.form>
        <p :if={@local_saved} id="local-interest-success" role="status" class="mt-4">
          {gettext("Your postal area is saved. Local invitations follow your account preference.")}
        </p>
        <div :if={@local_ready} id="local-paths" class="mt-5 space-y-3">
          <p :if={@local_groups == []}>{gettext("No group is listed for this postal area yet.")}</p>
          <ul :if={@local_groups != []} class="space-y-3">
            <li :for={group <- @local_groups} class="rounded-xl border border-stone-300 p-4">
              <h3 class="font-semibold">{group.name}</h3>
              <p>{group.description}</p>
              <a href={group.join_url} class="underline">{gettext("Ask to join")}</a>
            </li>
          </ul>
          <p>
            {gettext(
              "Meet people at an event or explore starting a local group. An incubator helps people develop a project together; choosing this path does not create membership."
            )}
          </p>
          <a href="https://luma.com/calendar/cal-tsYv79s4aTQC16Q" class="block underline">{gettext(
            "Upcoming events"
          )}</a>
          <a href="https://pauseai.info/local-organizing" class="block underline">{gettext(
            "Start a group"
          )}</a>
          <a
            :if={!@current_scope}
            href={
              ~p"/users/register?#{%{locale: @locale, fsa: @local_form[:fsa].value, return_to: if(@locale == "fr", do: "/fr/comprendre", else: "/en/learn")}}"
            }
            data-learning-register
            class="block underline"
          >{gettext("Save my postal area with an account")}</a>
        </div>
      </section>
      <section id="updates" class="border-t border-stone-200 bg-white">
        <div class="mx-auto max-w-5xl px-5 py-14">
          <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
            {updates_heading(@locale)}
          </h2>
          <div class="mt-8 grid gap-10 md:grid-cols-2">
            <section aria-labelledby="newsletter-heading">
              <h3 id="newsletter-heading" class="font-heading text-2xl">{gettext("Newsletter")}</h3>
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
                  <span class="text-sm leading-6 text-stone-700">
                    {consent_label(@locale)}
                    <.link
                      navigate={
                        if(@locale == "fr", do: ~p"/fr/confidentialite", else: ~p"/en/privacy")
                      }
                      class="ml-1 underline decoration-brand decoration-2 underline-offset-4"
                    >
                      {confidentiality_policy_label(@locale)}
                    </.link>
                  </span>
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
            </section>
            <section aria-labelledby="join-account-heading">
              <h3 id="join-account-heading" class="font-heading text-2xl">
                {gettext("Your account")}
              </h3>
              <p class="mt-3 leading-7 text-stone-600">
                {gettext("Keep a record of your actions and save resources to return to later.")}
              </p>
              <.link
                :if={!@current_scope}
                id="join-create-account"
                navigate={~p"/users/register?#{%{locale: @locale}}"}
                class="mt-5 inline-flex rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 hover:bg-brand-strong"
              >
                {gettext("Create an account")}
              </.link>
              <.link
                :if={@current_scope}
                id="join-my-account"
                navigate={if(@locale == "fr", do: ~p"/fr/tableau-de-bord", else: ~p"/en/dashboard")}
                class="mt-5 inline-flex rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 hover:bg-brand-strong"
              >
                {gettext("My dashboard")}
              </.link>
              <p class="mt-4 text-sm text-stone-600">
                {gettext("Creating an account does not subscribe you to the newsletter.")}
              </p>
              <p class="mt-8 leading-7 text-stone-600">
                {gettext("Meet other people at our gatherings and find ways to act together.")}
              </p>
              <a
                href="https://luma.com/calendar/cal-tsYv79s4aTQC16Q"
                class="mt-3 inline-block font-semibold underline decoration-brand decoration-2 underline-offset-4"
                target="_blank"
                rel="noopener noreferrer"
              >{gettext("Upcoming events")}</a>
            </section>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp bookmark_label(_locale), do: gettext("Bookmark")

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

  defp updates_heading(_locale), do: gettext("Stay informed")

  defp updates_note(_locale),
    do:
      gettext(
        "News about AI policy in Canada, meetings and ways to take part. Unsubscribe at any time."
      )

  defp email_label(_locale), do: gettext("Your email")

  defp consent_label(_locale),
    do: gettext("I agree to receive emails from PauseAI Canada. We do not sell your address.")

  defp confidentiality_policy_label(_locale), do: gettext("Read our privacy policy.")

  defp subscribe_cta(_locale), do: gettext("Sign me up")

  defp subscribing_label(_locale), do: gettext("Signing up…")

  defp subscribed_message(_locale),
    do: gettext("Done. Thank you — you will get the next mailing.")

  defp subscribe_error_message({:error, :consent_required}, _locale),
    do: gettext("Please tick the consent box before signing up.")

  defp subscribe_error_message({:error, :invalid_email}, _locale),
    do: gettext("That email does not look valid.")

  defp subscribe_error_message({:error, :not_configured}, _locale),
    do: gettext("The mailing list is not connected in this environment yet.")

  defp subscribe_error_message(_state, _locale),
    do: gettext("Sign-up failed. Please try again shortly.")
end
