defmodule PauseAiCaWeb.WarningShotLive do
  @moduledoc """
  The current Warning Shot activation: what happened, what followed, and the two
  things a visitor can do about it right now.

  A visitor can send the letter two ways. "Send it for me" hands it to Brevo
  with their address as reply-to; "I'll send it myself" hands it to their own
  mail client and needs no personal data at all. The postal code is used for a
  single lookup either way and is never stored.
  """

  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Campaigns
  alias PauseAiCa.Campaigns.Delivery
  alias PauseAiCa.Campaigns.Letter
  alias PauseAiCa.Campaigns.Update
  alias PauseAiCa.Campaigns.WarningShot

  @draft_languages ~w(bilingual en fr)

  @impl true
  def mount(_params, _session, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    campaign = Campaigns.current_warning_shot()
    copy = WarningShot.copy(campaign, locale)

    sender = %{
      "name" => "",
      "postal_code" => "",
      "draft_language" => default_draft_language(locale)
    }

    {:ok,
     socket
     |> assign(:locale, locale)
     |> assign(:page_title, copy.title)
     |> assign(:campaign, campaign)
     |> assign(:copy, copy)
     |> assign(:sender, sender)
     |> assign(:sender_form, to_form(sender, as: :sender))
     |> assign(:representatives, [])
     |> assign(:lookup_error, nil)
     |> assign(:letter, nil)
     |> assign(:letter_form, nil)
     |> assign(:send_mode, "assisted")
     |> assign(:send_form, to_form(%{"email" => "", "consent" => "false"}, as: :send))
     |> assign(:send_state, :idle)}
  end

  @impl true
  def handle_event("update-sender", %{"sender" => params}, socket) do
    {:noreply, socket |> put_sender(params) |> recompose()}
  end

  def handle_event("find-mp", %{"sender" => params}, socket) do
    socket = put_sender(socket, params)

    case Campaigns.find_members_of_parliament(socket.assigns.sender["postal_code"]) do
      {:ok, []} ->
        {:noreply, no_representatives(socket, :not_found)}

      {:ok, representatives} ->
        {:noreply,
         socket
         |> assign(:representatives, representatives)
         |> assign(:lookup_error, nil)
         |> recompose()}

      {:error, reason} ->
        {:noreply, no_representatives(socket, reason)}
    end
  end

  def handle_event("edit-letter", %{"letter" => params}, socket) do
    %Letter{} = draft = socket.assigns.letter
    letter = %Letter{draft | subject: params["subject"] || "", body: params["body"] || ""}

    {:noreply, socket |> assign(:letter, letter) |> assign(:letter_form, to_letter_form(letter))}
  end

  def handle_event("choose-send-mode", %{"mode" => mode}, socket) when mode in ~w(assisted diy) do
    {:noreply, socket |> assign(:send_mode, mode) |> assign(:send_state, :idle)}
  end

  def handle_event("update-send", %{"send" => params}, socket) do
    {:noreply, assign(socket, :send_form, to_form(send_params(params), as: :send))}
  end

  def handle_event("send-letter", %{"send" => params}, socket) do
    params = send_params(params)
    socket = assign(socket, :send_form, to_form(params, as: :send))

    cond do
      params["consent"] != "true" ->
        {:noreply, assign(socket, :send_state, {:error, :consent_required})}

      true ->
        supporter = %{name: socket.assigns.sender["name"], email: params["email"]}

        case Delivery.deliver(socket.assigns.letter, supporter) do
          {:ok, _result} -> {:noreply, assign(socket, :send_state, :sent)}
          {:error, reason} -> {:noreply, assign(socket, :send_state, {:error, reason})}
        end
    end
  end

  defp send_params(params) do
    %{
      "email" => params["email"] || "",
      "consent" => if(params["consent"] in ["true", "on"], do: "true", else: "false")
    }
  end

  defp put_sender(socket, params) do
    sender = %{
      "name" => params["name"] || "",
      "postal_code" => params["postal_code"] || "",
      "draft_language" => draft_language(params["draft_language"])
    }

    socket
    |> assign(:sender, sender)
    |> assign(:sender_form, to_form(sender, as: :sender))
  end

  defp no_representatives(socket, reason) do
    socket
    |> assign(:representatives, [])
    |> assign(:letter, nil)
    |> assign(:letter_form, nil)
    |> assign(:lookup_error, reason)
  end

  defp recompose(%{assigns: %{representatives: []}} = socket), do: socket

  defp recompose(socket) do
    sender = socket.assigns.sender

    letter =
      Campaigns.compose_letter(
        socket.assigns.representatives,
        String.to_existing_atom(sender["draft_language"]),
        %{name: sender["name"], postal_code: sender["postal_code"]}
      )

    socket |> assign(:letter, letter) |> assign(:letter_form, to_letter_form(letter))
  end

  defp to_letter_form(%Letter{} = letter) do
    to_form(%{"subject" => letter.subject, "body" => letter.body}, as: :letter)
  end

  defp default_draft_language("fr"), do: "fr"
  defp default_draft_language(_locale), do: "bilingual"

  defp draft_language(value) when value in @draft_languages, do: value
  defp draft_language(_value), do: "bilingual"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} locale={@locale}>
      <article>
        <p class="sticky top-[var(--header-height)] z-30 bg-brand px-5 py-3 text-center font-heading text-sm font-bold uppercase tracking-[0.16em] text-stone-950">
          {@copy.badge}
        </p>

        <section class="mx-auto max-w-5xl px-5 pt-14 pb-10">
          <h1 class="max-w-3xl font-heading text-5xl leading-[1.02] tracking-tight text-stone-950 sm:text-6xl">
            {@copy.title}
          </h1>
          <p class="mt-7 max-w-3xl text-xl leading-9 text-stone-700">{@copy.lede}</p>

          <div class="mt-10 border-l-4 border-brand bg-brand-wash p-7">
            <h2 class="font-heading text-2xl uppercase tracking-wide text-stone-950">
              {@copy.why_heading}
            </h2>
            <ul class="mt-4 space-y-3">
              <li :for={bullet <- @copy.why_bullets} class="flex gap-3 leading-7 text-stone-800">
                <span aria-hidden="true" class="mt-2.5 size-2 shrink-0 rounded-full bg-brand"></span>
                <span>{bullet}</span>
              </li>
            </ul>
          </div>

          <p class="mt-6 max-w-3xl text-sm leading-6 text-stone-500">{@copy.educational_note}</p>
        </section>

        <section id="act" class="border-y border-stone-200 bg-white">
          <div class="mx-auto max-w-5xl px-5 py-16">
            <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
              {@copy.act_heading}
            </h2>

            <div class="mt-8 grid gap-6 md:grid-cols-2">
              <div class="flex flex-col gap-3 rounded-2xl border border-stone-200 p-6 transition hover:shadow-md">
                <h3 class="font-heading text-2xl text-stone-950">{@copy.act_letter}</h3>
                <p class="leading-7 text-stone-600">{@copy.act_letter_note}</p>
                <a
                  id="jump-to-letter"
                  href="#letter"
                  class="mt-auto inline-flex w-fit rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 transition hover:-translate-y-0.5 hover:bg-brand-strong"
                >
                  {@copy.act_letter}
                </a>
              </div>

              <div class="flex flex-col gap-3 rounded-2xl border border-stone-200 p-6 transition hover:shadow-md">
                <h3 class="font-heading text-2xl text-stone-950">{@copy.act_join}</h3>
                <p class="leading-7 text-stone-600">{@copy.act_join_note}</p>
                <a
                  id="join-pauseai"
                  href={join_url(@campaign, @locale)}
                  rel="noreferrer"
                  class="mt-auto inline-flex w-fit rounded-full border-2 border-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 transition hover:-translate-y-0.5 hover:bg-brand-wash"
                >
                  {@copy.act_join}
                </a>
              </div>
            </div>

            <p class="mt-6">
              <a
                id="read-analysis"
                href={@campaign.links.analysis}
                rel="noreferrer"
                class="font-semibold text-stone-900 underline decoration-brand decoration-2 underline-offset-4"
              >
                {@copy.act_read} <span aria-hidden="true">↗</span>
              </a>
            </p>
          </div>
        </section>

        <section id="letter" class="mx-auto max-w-5xl px-5 py-16">
          <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
            {@copy.act_letter}
          </h2>
          <p class="mt-3 max-w-2xl leading-7 text-stone-600">{privacy_note(@locale)}</p>

          <.form
            for={@sender_form}
            id="mp-lookup-form"
            phx-change="update-sender"
            phx-submit="find-mp"
            class="mt-8 grid gap-x-6 sm:grid-cols-2"
          >
            <.input
              field={@sender_form[:name]}
              type="text"
              label={name_label(@locale)}
              autocomplete="name"
            />
            <.input
              field={@sender_form[:postal_code]}
              type="text"
              label={postal_code_label(@locale)}
              autocomplete="postal-code"
              maxlength="7"
              placeholder="H2X 1Y4"
            />
            <div class="sm:col-span-2">
              <.input
                field={@sender_form[:draft_language]}
                type="select"
                label={language_label(@locale)}
                options={draft_language_options(@locale)}
              />
            </div>
            <div class="sm:col-span-2">
              <button
                type="submit"
                id="find-mp"
                phx-disable-with={looking_up_label(@locale)}
                class="mt-2 rounded-full bg-stone-900 px-6 py-3 font-heading text-lg font-bold text-white transition hover:bg-stone-700"
              >
                {find_mp_label(@locale)}
              </button>
            </div>
          </.form>

          <p
            :if={@lookup_error}
            id="lookup-error"
            role="alert"
            class="mt-5 font-semibold text-red-700"
          >
            {lookup_error_message(@lookup_error, @locale)}
          </p>

          <div :if={@representatives != []} id="mp-results" class="mt-10">
            <h3 class="font-heading text-2xl text-stone-950">{mp_heading(@locale)}</h3>
            <ul class="mt-4 grid gap-3">
              <li
                :for={representative <- @representatives}
                class="rounded-2xl border border-stone-200 bg-white p-5 leading-7"
              >
                <p class="font-semibold text-stone-950">{representative.name}</p>
                <p class="text-stone-600">{representative.district}</p>
                <p :if={representative.party} class="text-sm text-stone-500">
                  {representative.party}
                </p>
                <p class="text-sm text-stone-500">{representative.email}</p>
              </li>
            </ul>
            <p class="mt-3 text-sm text-stone-500">{best_match_note(@locale)}</p>
          </div>

          <.form
            :if={@letter_form}
            for={@letter_form}
            id="letter-form"
            phx-change="edit-letter"
            class="mt-10"
          >
            <.input field={@letter_form[:subject]} type="text" label={subject_label(@locale)} />
            <p class="mb-1 text-sm text-stone-500">{body_hint(@locale)}</p>
            <.input
              field={@letter_form[:body]}
              type="textarea"
              label={body_label(@locale)}
              rows="20"
              class="w-full rounded-lg border border-stone-300 px-4 py-3 font-mono text-sm leading-6"
            />

            <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyLetter">
              export default {
                mounted() {
                  this.el.addEventListener("click", async () => {
                    const source = document.querySelector(this.el.dataset.target)
                    if (!source) return
                    const original = this.el.textContent
                    try {
                      await navigator.clipboard.writeText(source.value)
                      this.el.textContent = this.el.dataset.copied
                      setTimeout(() => { this.el.textContent = original }, 2000)
                    } catch (_error) {
                      source.focus()
                      source.select()
                    }
                  })
                }
              }
            </script>
          </.form>

          <div :if={@letter} id="send-options" class="mt-10">
            <h3 class="font-heading text-2xl text-stone-950">{send_heading(@locale)}</h3>

            <div class="mt-4 flex flex-wrap gap-2" role="tablist">
              <button
                :for={{mode, label} <- send_modes(@locale)}
                type="button"
                id={"send-mode-#{mode}"}
                role="tab"
                aria-selected={to_string(@send_mode == mode)}
                phx-click="choose-send-mode"
                phx-value-mode={mode}
                class={[
                  "rounded-full border-2 px-5 py-2.5 font-heading text-base font-bold transition",
                  if(@send_mode == mode,
                    do: "border-brand bg-brand text-stone-950",
                    else: "border-stone-300 text-stone-700 hover:border-brand"
                  )
                ]}
              >
                {label}
              </button>
            </div>

            <div :if={@send_mode == "assisted"} id="send-assisted" class="mt-6 max-w-2xl">
              <p class="leading-7 text-stone-600">{assisted_note(@locale)}</p>

              <.form
                for={@send_form}
                id="send-form"
                phx-change="update-send"
                phx-submit="send-letter"
                class="mt-4"
              >
                <.input
                  field={@send_form[:email]}
                  type="email"
                  label={email_label(@locale)}
                  autocomplete="email"
                />
                <label class="mt-2 flex items-start gap-3 leading-6">
                  <input type="hidden" name="send[consent]" value="false" />
                  <input
                    type="checkbox"
                    id="send-consent"
                    name="send[consent]"
                    value="true"
                    checked={@send_form[:consent].value == "true"}
                    class="mt-1 size-4 shrink-0"
                  />
                  <span class="text-sm text-stone-700">{consent_label(@locale)}</span>
                </label>

                <button
                  type="submit"
                  id="send-letter"
                  phx-disable-with={sending_label(@locale)}
                  class="mt-5 rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 transition hover:-translate-y-0.5 hover:bg-brand-strong"
                >
                  {send_for_me_cta(@locale)}
                </button>
              </.form>

              <p
                :if={@send_state == :sent}
                id="send-success"
                role="status"
                class="mt-5 font-semibold text-green-800"
              >
                {sent_message(@locale)}
              </p>
              <p
                :if={match?({:error, _reason}, @send_state)}
                id="send-error"
                role="alert"
                class="mt-5 font-semibold text-red-700"
              >
                {send_error_message(@send_state, @locale)}
              </p>
            </div>

            <div :if={@send_mode == "diy"} id="send-diy" class="mt-6 max-w-2xl">
              <p class="leading-7 text-stone-600">{diy_note(@locale)}</p>
              <div class="mt-4 flex flex-wrap gap-3">
                <a
                  id="open-mail-app"
                  href={Letter.mailto(@letter)}
                  class="rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 transition hover:-translate-y-0.5 hover:bg-brand-strong"
                >
                  {open_mail_label(@locale)}
                </a>
                <button
                  type="button"
                  id="copy-letter"
                  phx-hook=".CopyLetter"
                  data-target="#letter-form textarea"
                  data-copied={copied_label(@locale)}
                  class="rounded-full border-2 border-stone-300 px-6 py-3 font-heading text-lg font-bold text-stone-800 transition hover:border-brand"
                >
                  {copy_letter_label(@locale)}
                </button>
              </div>
            </div>
          </div>
        </section>

        <section id="developments" class="border-t border-stone-200 bg-white">
          <div class="mx-auto max-w-5xl px-5 py-16">
            <h2 class="font-heading text-3xl uppercase tracking-wide text-stone-950">
              {@copy.updates_heading}
            </h2>
            <p class="mt-3 text-sm text-stone-500">
              {String.replace(@copy.updates_note, "%{date}", Date.to_iso8601(@campaign.reviewed_on))}
            </p>

            <ol id="developments-list" class="mt-8 border-l-2 border-stone-200">
              <li
                :for={update <- @campaign.updates}
                id={update_id(update)}
                class="relative pb-9 pl-7 last:pb-0"
              >
                <span
                  aria-hidden="true"
                  class="absolute top-2 -left-[7px] size-3 rounded-full bg-brand"
                ></span>
                <time
                  datetime={Date.to_iso8601(update.date)}
                  class="font-heading text-sm font-bold tracking-[0.1em] text-brand-ink"
                >
                  {Date.to_iso8601(update.date)}
                </time>
                <h3 class="mt-1 font-heading text-2xl leading-snug text-stone-950">
                  <a
                    href={update.url}
                    rel="noreferrer"
                    class="underline decoration-brand decoration-2 underline-offset-4"
                  >
                    {Update.copy(update, @locale).title}
                  </a>
                </h3>
                <p class="mt-2 leading-7 text-stone-700">{Update.copy(update, @locale).summary}</p>
                <p class="mt-2 text-sm text-stone-500">
                  {@copy.source_label}: {update.publisher}<span
                    :if={Update.foreign_language?(update, @locale)}
                    class="ml-2 rounded border border-stone-300 px-1.5 py-0.5 text-xs uppercase"
                  >{update.language}</span>
                </p>
              </li>
            </ol>
          </div>
        </section>
      </article>
    </Layouts.app>
    """
  end

  # PauseAI's global onboarding form, prefilled with Canada and the reader's
  # language so a Canadian organizer picks the signup up.
  defp join_url(campaign, "fr"), do: campaign.links.join_fr
  defp join_url(campaign, _locale), do: campaign.links.join_en

  defp update_id(update) do
    slug = update.publisher |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
    "update-#{Date.to_iso8601(update.date)}-#{String.trim(slug, "-")}"
  end

  defp draft_language_options("fr"),
    do: [{"Bilingue", "bilingual"}, {"Français seulement", "fr"}, {"Anglais seulement", "en"}]

  defp draft_language_options(_locale),
    do: [{"Bilingual", "bilingual"}, {"English only", "en"}, {"French only", "fr"}]

  defp privacy_note("fr"),
    do:
      "Votre code postal sert à une seule recherche auprès de Represent (Open North) et n'est pas conservé. La lettre part de votre propre messagerie, pas de ce site."

  defp privacy_note(_locale),
    do:
      "Your postal code is used for a single lookup against Represent (Open North) and is not stored. The letter is sent from your own mail app, not from this site."

  defp name_label("fr"), do: "Votre nom"
  defp name_label(_locale), do: "Your name"

  defp postal_code_label("fr"), do: "Code postal"
  defp postal_code_label(_locale), do: "Postal code"

  defp language_label("fr"), do: "Langue de la lettre"
  defp language_label(_locale), do: "Letter language"

  defp find_mp_label("fr"), do: "Trouver mon député·e"
  defp find_mp_label(_locale), do: "Find my MP"

  defp looking_up_label("fr"), do: "Recherche…"
  defp looking_up_label(_locale), do: "Looking up…"

  defp mp_heading("fr"), do: "Votre député·e"
  defp mp_heading(_locale), do: "Your MP"

  defp best_match_note("fr"),
    do: "Il s'agit de la meilleure correspondance. Vérifiez avant d'envoyer."

  defp best_match_note(_locale), do: "This is a best match. Please check before sending."

  defp subject_label("fr"), do: "Objet"
  defp subject_label(_locale), do: "Subject"

  defp body_label("fr"), do: "Message"
  defp body_label(_locale), do: "Body"

  defp body_hint("fr"),
    do: "Personnalisez la lettre avant l'envoi. Une phrase à vous compte plus que le modèle."

  defp body_hint(_locale),
    do:
      "Personalize the letter before sending. One sentence of your own counts for more than the template."

  defp send_heading("fr"), do: "Envoyer"
  defp send_heading(_locale), do: "Send it"

  defp send_modes("fr"),
    do: [{"assisted", "Envoyez-le pour moi"}, {"diy", "Je l'envoie moi-même"}]

  defp send_modes(_locale), do: [{"assisted", "Send it for me"}, {"diy", "I'll send it myself"}]

  defp assisted_note("fr"),
    do:
      "Nous envoyons la lettre depuis PauseAI Canada, avec votre adresse en réponse pour que votre député·e puisse vous répondre directement. Nous ne conservons pas votre adresse."

  defp assisted_note(_locale),
    do:
      "We send the letter from PauseAI Canada with your address as reply-to, so your MP can answer you directly. We do not keep your address."

  defp diy_note("fr"),
    do:
      "Ouvrez la lettre dans votre propre messagerie. Rien ne nous est transmis: nous ne verrons ni votre adresse ni le texte final."

  defp diy_note(_locale),
    do:
      "Open the letter in your own mail app. Nothing reaches us: we never see your address or the final text."

  defp email_label("fr"), do: "Votre courriel"
  defp email_label(_locale), do: "Your email"

  defp consent_label("fr"),
    do:
      "J'autorise PauseAI Canada à envoyer cette lettre en mon nom à mon·ma député·e, avec mon courriel comme adresse de réponse."

  defp consent_label(_locale),
    do:
      "I authorize PauseAI Canada to send this letter to my MP on my behalf, with my email as the reply-to address."

  defp send_for_me_cta("fr"), do: "Envoyer la lettre"
  defp send_for_me_cta(_locale), do: "Send the letter"

  defp sending_label("fr"), do: "Envoi…"
  defp sending_label(_locale), do: "Sending…"

  defp sent_message("fr"),
    do:
      "Envoyé. Merci — les réponses des bureaux de député·es arrivent souvent en quelques jours."

  defp sent_message(_locale),
    do: "Sent. Thank you — replies from MP offices often arrive within a few days."

  defp send_error_message({:error, :consent_required}, "fr"),
    do: "Cochez la case d'autorisation avant l'envoi."

  defp send_error_message({:error, :consent_required}, _locale),
    do: "Please tick the authorization box before sending."

  defp send_error_message({:error, :invalid_email}, "fr"),
    do: "Ce courriel ne semble pas valide. Votre député·e en a besoin pour vous répondre."

  defp send_error_message({:error, :invalid_email}, _locale),
    do: "That email does not look valid. Your MP needs it to reply to you."

  defp send_error_message({:error, :no_recipient}, "fr"),
    do: "Aucun·e député·e sélectionné·e. Recherchez votre code postal d'abord."

  defp send_error_message({:error, :no_recipient}, _locale),
    do: "No MP selected. Look up your postal code first."

  defp send_error_message(_state, "fr"),
    do: "L'envoi a échoué. Réessayez, ou utilisez « Je l'envoie moi-même »."

  defp send_error_message(_state, _locale),
    do: "Sending failed. Try again, or use \"I'll send it myself\"."

  defp open_mail_label("fr"), do: "Ouvrir dans ma messagerie"
  defp open_mail_label(_locale), do: "Open in my email app"

  defp copy_letter_label("fr"), do: "Copier la lettre"
  defp copy_letter_label(_locale), do: "Copy the letter"

  defp copied_label("fr"), do: "Copié"
  defp copied_label(_locale), do: "Copied"

  defp lookup_error_message(:invalid_postal_code, "fr"),
    do: "Ce code postal ne semble pas valide. Exemple: H2X 1Y4."

  defp lookup_error_message(:invalid_postal_code, _locale),
    do: "That does not look like a Canadian postal code. Example: H2X 1Y4."

  defp lookup_error_message(:not_found, "fr"),
    do: "Aucun·e député·e trouvé·e pour ce code postal."

  defp lookup_error_message(:not_found, _locale), do: "No MP found for that postal code."

  defp lookup_error_message(:unavailable, "fr"),
    do:
      "Le service de recherche est indisponible pour le moment. Réessayez, ou écrivez directement à votre député·e."

  defp lookup_error_message(:unavailable, _locale),
    do: "The lookup service is unavailable right now. Try again, or write to your MP directly."
end
