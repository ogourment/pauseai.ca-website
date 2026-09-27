defmodule PauseAiCaWeb.DonateLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Donations
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_, _, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("Donate"),
       saved: false,
       selected_suggestion: nil,
       form: to_form(Donations.change(%{"locale" => locale}), as: "pledge")
     )}
  end

  @impl true
  def handle_event("validate", %{"pledge" => attrs}, socket) do
    changeset = Donations.change(Map.put(attrs, "locale", socket.assigns.locale))

    {:noreply,
     socket
     |> assign(:selected_suggestion, suggestion_for(attrs["amount_cad"]))
     |> assign(:form, to_form(%{changeset | action: :validate}, as: "pledge"))}
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
  def handle_event("choose_amount", %{"amount" => amount}, socket)
      when amount in ~w(25 100 500 2000) do
    attrs =
      socket.assigns.form.source
      |> Ecto.Changeset.apply_changes()
      |> Map.from_struct()
      |> Map.take([:name, :email, :amount_cad, :notes, :contact_consent, :locale])
      |> Map.put(:amount_cad, amount)

    {:noreply,
     socket
     |> assign(:selected_suggestion, amount)
     |> assign(:form, to_form(Donations.change(attrs), as: "pledge"))}
  end

  defp suggestion_for(amount) do
    with {:ok, value} <- Decimal.cast(amount) do
      Enum.find(~w(25 100 500 2000), &Decimal.equal?(value, Decimal.new(&1)))
    else
      _ -> nil
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
        <h1 class="font-heading text-5xl text-stone-950">
          {gettext("Help turn concern into action")}
        </h1>
        <div class="mt-7 grid items-start gap-8 md:grid-cols-[1fr_0.9fr]">
          <div>
            <p class="max-w-3xl text-xl leading-8 text-stone-700">
              {gettext(
                "On September 26, around 40 people gathered in Montréal to call for a coordinated pause in advanced AI development. Help us carry that call into neighbourhoods, community meetings and policy discussions."
              )}
            </p>
            <.link
              navigate={
                if @locale == "fr",
                  do: ~p"/fr/manifestation-montreal-2026-09-26",
                  else: ~p"/en/montreal-protest-2026-09-26"
              }
              class="mt-5 inline-block font-semibold underline decoration-brand decoration-2 underline-offset-4"
            >{gettext("See the Montréal protest")}</.link>
          </div>
          <figure>
            <img
              src={~p"/images/protest-2026-09-26/clara-lacasse-7.jpg"}
              width="3000"
              height="2400"
              alt={gettext("Demonstrators holding signs calling for a worldwide pause on AI")}
              class="h-auto w-full rounded-xl"
            />
            <figcaption class="mt-2 text-sm text-stone-600">
              {gettext("Montréal, September 26. Photo: Clara Lacasse.")}
            </figcaption>
          </figure>
        </div>
        <div class="mt-8 border-l-4 border-brand bg-brand-wash p-6">
          <h2 class="font-heading text-2xl">{gettext("Make a pledge today")}</h2>
          <p class="mt-3 leading-7">
            {gettext(
              "We are preparing our bank account. No payment is collected here. Leave your contact information and, if you wish, an amount you intend to give. We will contact you when we can receive donations."
            )}
          </p>
          <a
            href="#pledge-form"
            class="mt-4 inline-block font-semibold underline decoration-brand decoration-2 underline-offset-4"
          >
            {gettext("Go to the pledge form")}
          </a>
        </div>
        <h2 class="mt-10 font-heading text-3xl">{gettext("What your support makes possible")}</h2>
        <div id="funding-themes" class="mt-6 grid gap-5 sm:grid-cols-2">
          <section class="rounded-xl border border-stone-200 bg-white p-6">
            <h3 class="font-heading text-2xl">{gettext("Reach more people")}</h3>
            <p class="mt-2 leading-7 text-stone-700">
              {gettext(
                "Put clear information about AI risks and the call for a pause in neighbours’ hands and online feeds. We can count materials distributed and report the reach of public posts."
              )}
            </p>
            <ul class="mt-3 list-disc space-y-1 pl-5 text-sm leading-6 text-stone-600">
              <li>{gettext("Design and print flyers and posters")}</li>
              <li>{gettext("Manage social media")}</li>
              <li>{gettext("Photograph actions and write articles and other content")}</li>
            </ul>
          </section>
          <section class="rounded-xl border border-stone-200 bg-white p-6">
            <h3 class="font-heading text-2xl">{gettext("Bring people together")}</h3>
            <p class="mt-2 leading-7 text-stone-700">
              {gettext(
                "Hold welcoming local meetings where residents can plan actions and build the Montréal community. We can report how many gatherings took place."
              )}
            </p>
            <ul class="mt-3 list-disc pl-5 text-sm leading-6 text-stone-600">
              <li>{gettext("Rent meeting space and support accessible gatherings")}</li>
            </ul>
          </section>
          <section class="rounded-xl border border-stone-200 bg-white p-6">
            <h3 class="font-heading text-2xl">{gettext("Make the case for policy")}</h3>
            <p class="mt-2 leading-7 text-stone-700">
              {gettext(
                "Turn community concerns and evidence into briefs and fact sheets that elected representatives can act on. We can share the finished work publicly."
              )}
            </p>
            <ul class="mt-3 list-disc pl-5 text-sm leading-6 text-stone-600">
              <li>{gettext("Research policy and prepare briefs and fact sheets")}</li>
            </ul>
          </section>
          <section class="rounded-xl border border-stone-200 bg-white p-6">
            <h3 class="font-heading text-2xl">{gettext("Keep people connected")}</h3>
            <p class="mt-2 leading-7 text-stone-700">
              {gettext(
                "Maintain a site where people can learn, sign up to help and find the next action. We can report improvements as the tools become available."
              )}
            </p>
            <ul class="mt-3 list-disc pl-5 text-sm leading-6 text-stone-600">
              <li>{gettext("Develop and operate the website and connect the tools it needs")}</li>
            </ul>
          </section>
        </div>
        <div id="pledge-suggestions" class="mt-12">
          <h2 class="font-heading text-3xl">{gettext("Choose an amount that works for you")}</h2>
          <p class="mt-3 max-w-2xl leading-7 text-stone-700">
            {gettext(
              "These are suggested pledge sizes, not prices for a specific activity. You can enter any amount in the form. We will share actual costs as plans are confirmed."
            )}
          </p>
          <div class="mt-5 grid gap-3 sm:grid-cols-2">
            <button
              :for={
                {amount, outcome} <- [
                  {"25", gettext("Help share clear information")},
                  {"100", gettext("Help bring neighbours together")},
                  {"500", gettext("Help turn evidence into policy proposals")},
                  {"2000", gettext("Help keep people connected online")}
                ]
              }
              type="button"
              phx-click={
                JS.set_attribute({"value", amount}, to: "#pledge_amount_cad")
                |> JS.push("choose_amount", value: %{amount: amount})
              }
              phx-value-amount={amount}
              aria-pressed={to_string(@selected_suggestion == amount)}
              class="rounded-xl border-2 border-stone-300 bg-white p-4 text-left transition hover:border-brand hover:bg-brand-wash focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand aria-pressed:border-brand aria-pressed:bg-brand-wash"
            >
              <strong class="font-heading text-2xl">${amount}</strong>
              <span class="mt-1 block text-sm text-stone-700">{outcome}</span>
            </button>
          </div>
          <p
            :if={@selected_suggestion in ~w(25 100 500 2000)}
            class="mt-3 text-sm font-semibold"
            role="status"
          >
            {gettext("Suggested pledge selected: $%{amount} CAD", amount: @selected_suggestion)}
            <a
              href="#pledge-form"
              class="ml-2 underline decoration-brand decoration-2 underline-offset-4"
            >
              {gettext("Continue to the form")}
            </a>
          </p>
        </div>
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
