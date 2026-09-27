defmodule PauseAiCaWeb.DonateLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Donations

  @impl true
  def mount(_, _, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("Donate"),
       saved: false,
       form: to_form(Donations.change(%{"locale" => locale}), as: "pledge")
     )}
  end

  @impl true
  def handle_event("validate", %{"pledge" => attrs}, socket) do
    changeset = Donations.change(Map.put(attrs, "locale", socket.assigns.locale))
    {:noreply, assign(socket, :form, to_form(%{changeset | action: :validate}, as: "pledge"))}
  end

  def handle_event("save", %{"pledge" => attrs}, socket) do
    case Donations.pledge(Map.put(attrs, "locale", socket.assigns.locale)) do
      {:ok, _} ->
        {:noreply, assign(socket, :saved, true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: "pledge"))}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:form, to_form(Donations.change(attrs), as: "pledge"))
         |> put_flash(
           :error,
           gettext("We could not save your pledge right now. Please try again later.")
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      promote_warning_shot={false}
      translated_path={if @locale == "fr", do: ~p"/en/donate", else: ~p"/fr/faire-un-don"}
    >
      <section id="donate-page" class="mx-auto max-w-5xl px-5 py-14">
        <h1 class="font-heading text-5xl text-stone-950">{gettext("Help build PauseAI Canada")}</h1>
        <p class="mt-6 max-w-3xl text-xl leading-8 text-stone-700">
          {gettext("Your support helps turn public concern about AI into informed, organized action.")}
        </p>
        <div class="mt-8 border-l-4 border-brand bg-brand-wash p-6">
          <h2 class="font-heading text-2xl">{gettext("Make a pledge today")}</h2>
          <p class="mt-3 leading-7">
            {gettext(
              "We are preparing our bank account. No payment is collected here. Leave your contact information and, if you wish, an amount you intend to give. We will contact you when we can receive donations."
            )}
          </p>
        </div>
        <h2 class="mt-10 font-heading text-3xl">{gettext("What your support makes possible")}</h2>
        <ul class="mt-5 grid list-disc gap-3 pl-5 leading-7 sm:grid-cols-2">
          <li>{gettext("Designing and printing flyers and posters")}</li>
          <li>{gettext("Renting meeting space")}</li>
          <li>{gettext("Policy research")}</li>
          <li>{gettext("Managing social media")}</li>
          <li>{gettext("Photography, articles and other content")}</li>
          <li>{gettext("Website development, operations and systems integration")}</li>
        </ul>
        <div
          :if={@saved}
          id="pledge-saved"
          role="status"
          class="mt-10 rounded-xl border border-brand bg-white p-6"
        >
          <h2 class="font-heading text-2xl">{gettext("Thank you for your support")}</h2>
          <p>
            {gettext(
              "Your interest is recorded. We will contact you about your pledge when donations can be received. No payment has been taken."
            )}
          </p>
          <p>
            {gettext(
              "If you had already made a pledge with this email, your earlier details have been kept. Contact us to change them."
            )}
          </p>
          <a href="mailto:info@pauseai.ca" class="underline">{gettext("Contact us")}</a>
        </div>
        <.form
          :if={!@saved}
          for={@form}
          id="pledge-form"
          phx-submit="save"
          phx-change="validate"
          class="mt-10 max-w-2xl space-y-5 rounded-xl border bg-white p-6 [&_.label]:whitespace-normal"
        >
          <.input field={@form[:name]} label={gettext("Name")} autocomplete="name" required />
          <.input
            field={@form[:email]}
            label={gettext("Email")}
            type="email"
            autocomplete="email"
            required
          />
          <.input
            field={@form[:amount_cad]}
            label={gettext("Amount you intend to give (CAD, optional)")}
            type="number"
            min="0.01"
            step="0.01"
          />
          <.input
            field={@form[:notes]}
            label={gettext("Notes (optional)")}
            type="textarea"
            maxlength="2000"
          />
          <div class="hidden" aria-hidden="true">
            <input name="pledge[website]" tabindex="-1" autocomplete="off" />
          </div>
          <.input
            field={@form[:contact_consent]}
            type="checkbox"
            label={gettext("You may contact me about this pledge.")}
            required
          />
          <p class="text-sm">
            {gettext("This does not subscribe you to a mailing list.")}
            <a
              href={if @locale == "fr", do: "/fr/confidentialite", else: "/en/privacy"}
              class="ml-1 underline"
            >{gettext("Privacy")}</a>
          </p>
          <.button phx-disable-with={gettext("Saving…")}>{gettext("Save my pledge")}</.button>
        </.form>
        <p class="mt-10 text-sm text-stone-600">
          {gettext("PauseAI Canada")} · {gettext("Corporation number")}: 1819452-1 · {gettext(
            "Business Number"
          )}: 791107246
        </p>
      </section>
    </Layouts.app>
    """
  end
end
