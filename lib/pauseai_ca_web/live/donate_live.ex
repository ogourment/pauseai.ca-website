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
       campaign_mode: Application.get_env(:pauseai_ca, :manifund_donations_enabled, false),
       campaign: PauseAiCa.Donations.Campaign.current(),
       saved: false,
       selected_suggestion: nil,
       form: to_form(Donations.change(%{"locale" => locale}), as: "pledge")
     )}
  end

  @impl true
  def handle_event(_, _, %{assigns: %{campaign_mode: true}} = socket), do: {:noreply, socket}

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
      |> Map.take([:name, :email, :amount_cad, :notes, :contact_consent, :locale, :frequency])
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
    <%= if @campaign_mode do %>
      <.campaign_page {assigns} />
    <% else %>
      <.legacy_pledge_page {assigns} />
    <% end %>
    """
  end

  defp campaign_page(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      promote_warning_shot={false}
      translated_path={if @locale == "fr", do: ~p"/en/donate", else: ~p"/fr/faire-un-don"}
    >
      <section id="donate-page" class="mx-auto max-w-3xl px-5 py-12">
        <h1 class="font-heading text-4xl sm:text-5xl text-stone-950">
          {gettext("Support PauseAI Canada")}
        </h1>
        <p class="mt-5 text-xl leading-8 text-stone-700">
          {gettext(
            "Help Canadians make the case for an international pause on the development of the most powerful AI systems. Your donation helps people organize locally, explain the risks, and bring concrete requests to elected representatives."
          )}
        </p>
        <section
          id="manifund-campaign"
          class="mt-7 rounded-xl border border-stone-200 bg-white p-5 sm:p-6"
        >
          <h2 class="font-heading text-2xl">{gettext("What your support makes possible")}</h2>
          <p class="mt-3 leading-7 text-stone-700">
            {gettext(
              "Support local groups in Toronto and across Canada, public meetings and outreach materials, and research and briefings for conversations with MPs."
            )}
          </p>
          <%= if match?({:ok, _}, @campaign) do %>
            <% {:ok, campaign} = @campaign %>
            <a
              id="manifund-donate"
              phx-hook="PauseAiCaWeb.Layouts.TrackOutbound"
              data-donation="manifund"
              target="_blank"
              rel="noopener noreferrer"
              href={campaign.url}
              class="mt-5 inline-block rounded-lg bg-brand px-5 py-3 font-semibold text-stone-950 hover:bg-brand-strong"
            >
              {gettext("Donate on Manifund")} <span aria-hidden="true">↗</span>
              <span class="sr-only">{gettext("Opens in a new tab")}</span>
            </a>
            <p id="manifund-account-requirement" class="mt-3 text-sm leading-6 text-stone-700">
              {gettext(
                "A Manifund account is required to donate. You can read the full proposal without an account."
              )}
            </p>
            <p class="mt-2 text-sm leading-6">
              <a id="manifund-proposal" href={campaign.url} class="underline underline-offset-4">{gettext(
                "Read the full proposal"
              )}</a>
            </p>
          <% else %>
            <p id="manifund-unavailable" role="status" class="mt-4 leading-7">
              {gettext(
                "The Manifund campaign link is unavailable here. You can still donate by Interac below."
              )}
            </p>
          <% end %>
        </section>
        <section id="donate-interac" class="mt-8 border-l-4 border-brand bg-brand-wash p-5 sm:p-6">
          <h2 class="font-heading text-2xl">{gettext("Or donate by Interac e-Transfer")}</h2>
          <p class="mt-3 leading-7">
            {gettext(
              "Send your donation from your banking app to the address below. Autodeposit is enabled. Check that the recipient name is PauseAI Canada before confirming."
            )}
          </p>
          <p class="mt-3 break-all font-semibold">
            <span id="donation-email" class="select-all">pauseaicanada@proton.me</span>
          </p>
          <p class="mt-2">{gettext("Recipient")}: <strong>PauseAI Canada</strong></p>
        </section>
        <p class="mt-8 text-sm text-stone-600">
          {gettext("PauseAI Canada")} · {gettext("Corporation number")}: 1819452-1 · {gettext(
            "Business Number"
          )}: 791107246
        </p>
      </section>
    </Layouts.app>
    """
  end

  defp legacy_pledge_page(assigns) do
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
          {gettext("Support PauseAI Canada")}
        </h1>
        <div class="mt-7 grid items-start gap-8 md:grid-cols-[1fr_0.9fr]">
          <div>
            <p class="max-w-3xl text-xl leading-8 text-stone-700">
              {gettext(
                "Around 40 people joined our September 26 demonstration in Montréal. Your support will help us print information, hold meetings and workshops, and put proposals before elected representatives."
              )}
            </p>
          </div>
          <figure>
            <picture>
              <source
                type="image/webp"
                srcset={"#{~p"/images/protest-2026-09-26/clara-lacasse-7-small.webp"} 640w, #{~p"/images/protest-2026-09-26/clara-lacasse-7.webp"} 1200w"}
                sizes="(min-width: 768px) 580px, calc(100vw - 40px)"
              />
              <img
                src={~p"/images/protest-2026-09-26/clara-lacasse-7.jpg"}
                width="1200"
                height="960"
                alt={gettext("Demonstrators holding signs calling for a worldwide pause on AI")}
                class="h-auto w-full rounded-xl"
              />
            </picture>
            <figcaption class="mt-2 text-sm text-stone-600">
              {gettext("Montréal, September 26. Photo: Clara Lacasse.")}
            </figcaption>
          </figure>
        </div>
        <div id="donate-interac" class="mt-8 border-l-4 border-brand bg-brand-wash p-6">
          <h2 class="font-heading text-2xl">{gettext("Donate by Interac e-Transfer")}</h2>
          <p class="mt-3 leading-7">
            {gettext(
              "Send your donation from your banking app to the address below. Autodeposit is enabled. Check that the recipient name is PauseAI Canada before confirming."
            )}
          </p>
          <p class="mt-3 break-all text-xl font-semibold">
            <span id="donation-email" class="select-all">pauseaicanada@proton.me</span>
          </p>
          <p class="mt-2">{gettext("Recipient")}: <strong>PauseAI Canada</strong></p>
          <p class="mt-3 text-sm">
            {gettext("You can donate directly without completing the pledge form.")}
          </p>
          <a
            href="#pledge-form"
            class="mt-4 inline-block font-semibold underline decoration-brand decoration-2 underline-offset-4"
          >
            {gettext("Prefer to make a pledge?")}
          </a>
        </div>
        <h2 class="mt-10 font-heading text-3xl">{gettext("What your support makes possible")}</h2>
        <div id="funding-themes" class="mt-6 grid gap-5 sm:grid-cols-2">
          <section class="rounded-xl border border-stone-200 bg-white p-6">
            <h3 class="font-heading text-2xl">{gettext("Reach more people")}</h3>
            <p class="mt-2 leading-7 text-stone-700">
              {gettext(
                "Explain AI risks and our call for a pause through printed materials, photographs, articles and social media."
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
                "Hold meetings and workshops where people can ask questions, learn and plan local activities. Travel helps us meet people in more parts of Canada."
              )}
            </p>
            <ul class="mt-3 list-disc space-y-1 pl-5 text-sm leading-6 text-stone-600">
              <li>{gettext("Rent meeting space and support accessible gatherings")}</li>
              <li>{gettext("Design and facilitate workshops")}</li>
              <li>{gettext("Cover travel costs to reach more communities across Canada")}</li>
            </ul>
          </section>
          <section class="rounded-xl border border-stone-200 bg-white p-6">
            <h3 class="font-heading text-2xl">{gettext("Make the case for policy")}</h3>
            <p class="mt-2 leading-7 text-stone-700">
              {gettext(
                "Prepare research, briefs and fact sheets to support specific requests to governments."
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
                "Keep the website, email lists and volunteer signup tools working, and pay for the software used to organize our activities."
              )}
            </p>
            <ul class="mt-3 list-disc pl-5 text-sm leading-6 text-stone-600">
              <li>{gettext("Develop and operate the website and connect the tools it needs")}</li>
              <li>
                {gettext(
                  "Pay for video conferencing and software for communication, design and organizing"
                )}
              </li>
            </ul>
          </section>
        </div>
        <div id="pledge-suggestions" class="mt-12">
          <h2 class="font-heading text-3xl">{gettext("Make a pledge")}</h2>
          <p class="mt-3 max-w-2xl leading-7 text-stone-700">
            {gettext(
              "Choose a suggested amount or enter your own for a future contribution. We will contact you about your pledge. This form does not send a payment."
            )}
          </p>
          <div class="mt-5 grid gap-3 sm:grid-cols-2">
            <button
              :for={amount <- ~w(25 100 500 2000)}
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
              "Your pledge is recorded. We will contact you about it. No payment has been taken through this form."
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
            field={@form[:frequency]}
            label={gettext("Contribution frequency")}
            type="select"
            options={[{gettext("One-time"), "one_time"}, {gettext("Monthly"), "monthly"}]}
            required
          />
          <.input
            field={@form[:amount_cad]}
            label={gettext("Amount you intend to give (CAD, optional)")}
            type="number"
            min="0.01"
            step="0.01"
          />
          <p
            :if={@form[:frequency].value == "monthly"}
            id="monthly-pledge-help"
            class="text-sm text-stone-600"
          >
            {gettext(
              "For a monthly pledge, enter the amount you intend to give each month. No recurring payment is set up here."
            )}
          </p>
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
          <.button phx-disable-with={gettext("Saving…")}>{gettext("Save")}</.button>
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
