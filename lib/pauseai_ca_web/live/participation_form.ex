defmodule PauseAiCaWeb.ParticipationForm do
  use PauseAiCaWeb, :live_component
  alias PauseAiCa.Participation
  @impl true
  def update(%{submit_mp_choices: params}, socket) do
    if Enum.any?(~w(account newsletter local), &(params[&1] == "true")) do
      save_choices(params, socket)
      |> then(fn {:noreply, socket} -> {:ok, socket} end)
    else
      {:ok, socket}
    end
  end

  def update(assigns, socket) do
    socket = assign(socket, Map.drop(assigns, [:intent, :city]))
    socket = assign_new(socket, :show_ctas, fn -> Map.get(assigns, :show_ctas, true) end)
    socket = assign_new(socket, :group_focused, fn -> false end)
    socket = assign_new(socket, :group_cities, fn -> [] end)
    socket = assign_new(socket, :selected_group, fn -> nil end)
    socket = assign_new(socket, :selected_group_id, fn -> nil end)

    if Map.has_key?(socket.assigns, :form) do
      {:ok, socket}
    else
      intent = Map.get(assigns, :intent, "newsletter")
      form_as = if Map.get(assigns, :registration, false), do: "user", else: "participation"
      user = if assigns.current_scope, do: assigns.current_scope.user
      local = intent in ~w(waitlist help)

      params = %{
        "email" => if(user, do: user.email, else: ""),
        "name" => if(user, do: user.name || "", else: ""),
        "phone" => if(user, do: user.phone || "", else: ""),
        "fsa" => if(user, do: user.fsa || "", else: ""),
        "location" => if(user, do: user.fsa || "", else: ""),
        "postal_code" => if(user, do: user.postal_code || "", else: ""),
        "city" => Map.get(assigns, :city, ""),
        "help_text" => "",
        "newsletter" => to_string(intent == "mp"),
        "account" => to_string(intent in ~w(account action mp)),
        "local" => to_string(local),
        "local_kind" => if(intent == "help", do: "help", else: "waitlist")
      }

      {:ok,
       socket
       |> assign(
         form_as: form_as,
         params: params,
         form: to_form(params, as: form_as),
         intent: intent,
         state: :idle,
         explicit_choices: [],
         form_id:
           if(Map.get(assigns, :registration, false),
             do: "registration_form",
             else: "participation-form"
           )
       )}
    end
  end

  @impl true
  def handle_event(event, %{"user" => raw} = params, socket) when event in ["save", "validate"] do
    handle_event(event, Map.put(Map.delete(params, "user"), "participation", raw), socket)
  end

  def handle_event(
        "choose-group",
        %{"group-id" => group_id},
        %{assigns: %{group_focused: true}} = socket
      ) do
    case PauseAiCa.Incubators.public_group(group_id) do
      {:ok, group} ->
        params =
          socket.assigns.params
          |> Map.put("local", "true")
          |> Map.put("local_kind", "waitlist")

        name = if socket.assigns.locale == "fr", do: group.name_fr, else: group.name_en

        {:noreply,
         assign(socket,
           intent: "waitlist",
           params: params,
           selected_group: name,
           selected_group_id: group.group_id,
           form: to_form(params, as: socket.assigns.form_as),
           state: :idle
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("choose", %{"intent" => intent}, socket)
      when intent in ~w(newsletter action account waitlist help) do
    explicit = socket.assigns.explicit_choices
    params = socket.assigns.params

    params =
      if "account" in explicit,
        do: params,
        else: Map.put(params, "account", to_string(intent in ["account", "action"]))

    params =
      if "local" in explicit,
        do: params,
        else: Map.put(params, "local", to_string(intent in ["waitlist", "help"]))

    params =
      if intent in ["waitlist", "help"], do: Map.put(params, "local_kind", intent), else: params

    socket =
      if socket.assigns.group_focused && intent == "help",
        do: assign(socket, selected_group: nil, selected_group_id: nil),
        else: socket

    {:noreply,
     assign(socket,
       intent: intent,
       params: params,
       form: to_form(params, as: socket.assigns.form_as),
       state: :idle
     )}
  end

  def handle_event("restore-draft", %{"values" => values}, socket) do
    params = parameters(values, socket.assigns.current_scope, socket.assigns.params)

    params =
      case socket.assigns.intent do
        value when value in ["waitlist", "help"] ->
          params
          |> Map.put("local", "true")
          |> Map.put("local_kind", value)
          |> Map.put("city", socket.assigns.params["city"])

        value when value in ["action", "account"] ->
          Map.put(params, "account", "true")

        _ ->
          params
      end

    {:noreply, assign(socket, params: params, form: to_form(params, as: socket.assigns.form_as))}
  end

  def handle_event("validate", %{"participation" => raw} = event, socket) do
    params = parameters(raw, socket.assigns.current_scope, socket.assigns.params)

    changed =
      case event["_target"] do
        [prefix, field] when prefix in ["user", "participation"] ->
          [field]

        _ ->
          Enum.filter(["account", "newsletter", "local"], &(raw[&1] != socket.assigns.params[&1]))
      end

    explicit =
      Enum.uniq(
        socket.assigns.explicit_choices ++
          Enum.filter(changed, &(&1 in ["account", "newsletter", "local"]))
      )

    changeset = form_changeset(params, socket.assigns)

    {:noreply,
     assign(socket,
       params: params,
       form: to_form(%{changeset | action: :validate}, as: socket.assigns.form_as),
       explicit_choices: explicit,
       state: :idle
     )}
  end

  def handle_event("save", %{"participation" => raw}, socket) do
    params = parameters(raw, socket.assigns.current_scope, socket.assigns.params)
    params = Map.reject(params, fn {key, _} -> String.starts_with?(key, "_unused_") end)
    params = if socket.assigns.intent == "mp", do: mp_parameters(params), else: params

    if socket.assigns.intent == "mp" do
      changeset = form_changeset(params, socket.assigns)

      if changeset.valid? do
        send(self(), {:prepare_mp_letter, params})

        {:noreply,
         assign(socket,
           params: params,
           form: to_form(params, as: socket.assigns.form_as),
           state: :idle
         )}
      else
        {:noreply,
         assign(socket,
           params: params,
           form: to_form(%{changeset | action: :insert}, as: socket.assigns.form_as),
           state: :invalid
         )}
      end
    else
      save_choices(params, socket)
    end
  end

  defp save_choices(params, socket) do
    locale = socket.assigns.locale

    context =
      Map.get(socket.assigns, :context, %{
        "locale" => locale,
        "source" => "home_footer",
        "return_to" => if(locale == "fr", do: "/fr/tableau-de-bord", else: "/en/dashboard")
      })

    context =
      if socket.assigns.intent in ["account", "action"] && context["source"] in [nil, "unknown"] &&
           !context["bookmark"] &&
           context["basket"] in [nil, []],
         do:
           Map.put(
             context,
             "return_to",
             if(locale == "fr",
               do: "/fr/actions#action-editor",
               else: "/en/actions#action-editor"
             )
           ),
         else: context

    context =
      if socket.assigns.selected_group_id && params["local"] == "true",
        do: Map.put(context, "incubator_group_id", socket.assigns.selected_group_id),
        else: context

    url_fun = fn
      :account, {token, flow} ->
        PauseAiCaWeb.Site.url(locale, ~p"/users/log-in/#{token}?#{%{flow: flow, locale: locale}}")

      :confirm, token ->
        PauseAiCaWeb.Site.url(
          locale,
          ~p"/participation/confirm?#{%{token: token, locale: locale}}"
        )

      :withdraw, token ->
        PauseAiCaWeb.Site.url(
          locale,
          ~p"/participation/withdraw?#{%{token: token, locale: locale}}"
        )
    end

    case Participation.request(attributes(params, locale), context, url_fun) do
      {:ok, _} ->
        {:noreply,
         assign(socket,
           params: params,
           form: to_form(params, as: socket.assigns.form_as),
           state: :pending
         )}

      {:error, %Ecto.Changeset{} = c} ->
        {:noreply,
         assign(socket,
           params: params,
           form: to_form(%{c | action: :insert}, as: socket.assigns.form_as),
           state: :invalid
         )}

      {:error, :changed_choices_cooldown} ->
        {:noreply,
         assign(socket,
           params: params,
           form: to_form(params, as: socket.assigns.form_as),
           state: :cooldown
         )}

      {:error, _} ->
        {:noreply,
         assign(socket,
           params: params,
           form: to_form(params, as: socket.assigns.form_as),
           state: :delivery_error
         )}
    end
  end

  defp parameters(raw, scope, prior) do
    raw =
      Map.merge(
        Map.reject(prior, fn {key, _} -> String.starts_with?(key, "_unused_") end),
        Map.filter(raw, fn {key, _} ->
          key in ~w(email name phone fsa location postal_code city help_text newsletter account local) ||
            String.starts_with?(key, "_unused_")
        end)
      )

    if scope && scope.user, do: Map.put(raw, "email", scope.user.email), else: raw
  end

  defp form_changeset(params, %{intent: "mp", locale: locale}) do
    params = mp_parameters(params)

    PauseAiCa.Participation.Request.changeset(
      %PauseAiCa.Participation.Request{},
      attributes(params, locale),
      true
    )
    |> Ecto.Changeset.validate_required([:name])
    |> Ecto.Changeset.cast(params, [:postal_code])
    |> Ecto.Changeset.validate_required([:postal_code])
    |> Ecto.Changeset.validate_format(
      :postal_code,
      ~r/^[ABCEGHJ-NPRSTVXY][0-9][ABCEGHJ-NPRSTVWXYZ] ?[0-9][ABCEGHJ-NPRSTVWXYZ][0-9]$/i,
      message: dgettext_noop("errors", "enter a full Canadian postal code")
    )
  end

  defp form_changeset(params, assigns),
    do: Participation.change(attributes(params, assigns.locale))

  defp mp_parameters(params) do
    postal = (params["postal_code"] || "") |> String.trim() |> String.upcase()
    params |> Map.put("postal_code", postal) |> Map.put("location", String.slice(postal, 0, 3))
  end

  defp attributes(params, locale) do
    params
    |> Map.take(~w(email name phone location city help_text newsletter account local))
    |> Map.put("phone", if(params["account"] == "true", do: params["phone"]))
    |> Map.put("locale", locale)
    |> Map.put("local_kind", if(params["local"] == "true", do: params["local_kind"]))
    |> Map.put("city", if(params["local"] == "true", do: params["city"]))
    |> Map.put(
      "help_text",
      if(params["local"] == "true" && params["local_kind"] == "help", do: params["help_text"])
    )
  end

  defp submit_label("newsletter", _), do: gettext("Subscribe")
  defp submit_label("waitlist", _), do: gettext("Join the waitlist")
  defp submit_label("help", _), do: gettext("Offer my help")

  defp submit_label(_, scope),
    do: if(scope, do: gettext("Save my choices"), else: gettext("Create an account"))

  defp selected_submit_label("mp", _scope, _params), do: gettext("Continue to my letter")

  defp selected_submit_label(intent, scope, params) do
    case Enum.find(ordered_choices(intent, scope), fn {key, _} ->
           params[Atom.to_string(key)] == "true"
         end) do
      {:newsletter, _} -> submit_label("newsletter", scope)
      {:account, _} -> submit_label("account", scope)
      {:local, _} -> submit_label(params["local_kind"], scope)
      nil -> gettext("Continue")
    end
  end

  defp ordered_choices(intent, scope) do
    choices = %{
      newsletter: gettext("Subscribe me to the PauseAI Canada newsletter."),
      account:
        if(scope,
          do: gettext("Use my account to save and record my actions."),
          else: gettext("Create an account to save and record my actions.")
        ),
      local: gettext("Contact me about joining or helping a local group.")
    }

    order =
      cond do
        intent == "newsletter" -> [:newsletter, :account, :local]
        intent in ["waitlist", "help"] -> [:local, :account, :newsletter]
        true -> [:account, :newsletter, :local]
      end

    order = if intent == "mp", do: [:account, :newsletter], else: order
    Enum.map(order, &{&1, choices[&1]})
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="participation" class="space-y-7">
      <div
        :if={!@registration && @show_ctas}
        class="grid grid-cols-2 gap-3 max-w-2xl"
        id="participation-ctas"
      >
        <button
          type="button"
          phx-click="choose"
          phx-value-intent="newsletter"
          phx-target={@myself}
          aria-pressed={@intent == "newsletter"}
          aria-label={gettext("Get updates")}
          class="rounded-xl border border-stone-300 bg-white p-4 text-left hover:border-brand"
        >
          <span class="block font-heading text-2xl font-bold">{gettext("Get updates")}</span>
          <span class="mt-1 block text-sm text-stone-600">{gettext("Canadian news and meetings")}</span>
        </button>
        <button
          type="button"
          phx-click="choose"
          phx-value-intent="action"
          phx-target={@myself}
          aria-pressed={@intent != "newsletter"}
          aria-label={gettext("Take action")}
          class="rounded-xl border border-stone-300 bg-white p-4 text-left hover:border-brand"
        >
          <span class="block font-heading text-2xl font-bold">{gettext("Take action")}</span>
          <span class="mt-1 block text-sm text-stone-600">{gettext("On your own or with others")}</span>
        </button>
      </div>
      <div class="max-w-2xl">
        <h2 class="font-heading text-3xl">
          {cond do
            @group_focused ->
              gettext("Join a waitlist or help start an incubator")

            @intent == "mp" ->
              gettext("Your details and choices")

            @intent == "newsletter" ->
              gettext("Newsletter")

            @intent in ["waitlist", "help"] && @params["city"] not in [nil, ""] ->
              gettext("%{city}: join the waitlist or offer help", city: @params["city"])

            @registration ->
              gettext("Create an account")

            true ->
              gettext("Choose how to take part")
          end}
        </h2>
        <div
          :if={@intent not in ["newsletter", "mp"]}
          id="participation-motivations"
          class="mt-4 flex flex-wrap gap-2"
        >
          <button
            :for={
              {kind, label} <-
                [
                  {"account", gettext("Record my actions")},
                  {"waitlist", gettext("Join the waitlist")},
                  {"help",
                   if(@group_focused,
                     do: gettext("Help start an incubator"),
                     else: gettext("I can help")
                   )}
                ]
                |> Enum.reject(fn {kind, _} -> @group_focused && kind == "account" end)
            }
            type="button"
            phx-click="choose"
            phx-value-intent={kind}
            phx-target={@myself}
            aria-pressed={@intent == kind || (kind == "account" && @intent == "action")}
            class={"rounded-lg border px-3 py-2 text-sm font-semibold " <> if(@intent == kind || (kind == "account" && @intent == "action"), do: "border-brand bg-brand-wash", else: "border-stone-300 bg-white")}
          >{label}</button>
        </div>
        <p class="mt-3 text-sm text-stone-600">
          {gettext("Enter your details once and choose the options you want.")}
        </p>
        <.form
          for={@form}
          id={@form_id}
          phx-hook="FormDraft"
          data-draft-prefix={@form_as}
          data-draft-key={"pauseai:participation:" <> if(@current_scope, do: @current_scope.user.id, else: "anonymous") <> if(@intent == "mp", do: ":mp", else: "")}
          phx-change="validate"
          phx-submit="save"
          phx-target={@myself}
          class="mt-5"
        >
          <div class="grid grid-cols-[minmax(0,1fr)_132px] gap-3">
            <.input
              field={@form[:name]}
              label={gettext("Name")}
              autocomplete="name"
              maxlength="160"
            />
            <div>
              <.input
                field={if @intent == "mp", do: @form[:postal_code], else: @form[:location]}
                label={if @intent == "mp", do: gettext("Postal code"), else: gettext("FSA")}
                placeholder={if @intent == "mp", do: "H2X 1Y4", else: "H2X"}
                maxlength={if @intent == "mp", do: "7", else: "3"}
                spellcheck="false"
                aria-describedby="participation-fsa-help"
              />
              <p
                :if={@intent != "mp"}
                id="participation-fsa-help"
                class="mt-1 text-xs leading-tight text-stone-600"
              >
                {gettext("First three characters of your postal code, e.g. H2X.")}
              </p>
            </div>
            <p
              :if={@intent == "mp"}
              id="participation-fsa-help"
              class="col-span-2 mb-2 text-xs leading-tight text-stone-600"
            >
              {gettext(
                "Full postal code to find your MP. Its first three characters (FSA) identify your newsletter area."
              )}
            </p>
          </div>
          <.input
            id={if(@registration, do: "registration_form_email", else: "participation_email")}
            field={@form[:email]}
            type="email"
            label={if(@registration, do: gettext("Email"), else: gettext("Your email"))}
            aria-invalid={to_string(@form[:email].errors != [])}
            autocomplete="email"
            required
            readonly={!!@current_scope}
          />
          <.input
            :if={@params["account"] == "true"}
            field={@form[:phone]}
            type="tel"
            label={gettext("Phone (optional)")}
            autocomplete="tel"
            maxlength="40"
          />
          <fieldset class="mt-3 space-y-3">
            <legend class="sr-only">{gettext("Your choices")}</legend>
            <.input
              :for={{field, label} <- ordered_choices(@intent, @current_scope)}
              field={@form[field]}
              type="checkbox"
              label={label}
            />
          </fieldset>
          <div
            :if={@params["local"] == "true"}
            id="participation-local"
            class="mt-4 rounded-lg border border-stone-200 p-4"
          >
            <p
              :if={@selected_group}
              id="participation-selected-group"
              class="mb-3 text-sm font-semibold"
            >
              {gettext("Waitlist for %{group}", group: @selected_group)}
            </p>
            <.input
              field={@form[:city]}
              label={gettext("Where would you like to get involved?")}
              autocomplete="address-level2"
              placeholder="Toronto"
              list={if @group_focused, do: "participation-group-cities"}
            />
            <datalist :if={@group_focused} id="participation-group-cities">
              <option :for={city <- @group_cities} value={city} />
            </datalist>
            <input type="hidden" name={@form_as <> "[local_kind]"} value={@params["local_kind"]} />
            <.input
              :if={@params["local_kind"] == "help"}
              field={@form[:help_text]}
              type="textarea"
              label={gettext("How would you like to help?")}
              maxlength="2000"
            />
            <p class="mt-2 text-sm text-stone-600">
              {gettext("We will email you about your request. You can withdraw it at any time.")}
            </p>
          </div>
          <p :if={@intent == "mp"} id="mp-choices-note" class="mt-4 text-sm text-stone-600">
            {gettext(
              "You can contact your MP without an account or newsletter subscription. If you select either option, we will also email you a link to confirm your choices."
            )}
          </p>
          <p class="mt-4 text-sm">
            <.link
              href={if(@locale == "fr", do: ~p"/fr/confidentialite", else: ~p"/en/privacy")}
              class="underline"
            >{gettext("Read our privacy policy.")}</.link>
          </p>
          <button
            id="participation-submit"
            type="submit"
            phx-disable-with={gettext("Sending…")}
            class="mt-5 rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950"
          >{if @registration,
            do: gettext("Email me a secure link"),
            else: selected_submit_label(@intent, @current_scope, @params)}</button>
        </.form>
        <p
          :if={@state == :invalid}
          id="participation-validation"
          role="alert"
          class="mt-4 text-red-800"
        >
          {gettext("Please check the highlighted fields.")}
        </p>
        <p
          :if={@state == :pending}
          id="account-email-pending"
          role="status"
          class="mt-4 rounded-lg bg-brand-wash p-4"
        >
          {gettext("Check your email to confirm your choices. You can keep browsing while you wait.")}
        </p>
        <.dev_mailbox_link :if={@state == :pending} />
        <p
          :if={@state == :cooldown}
          id="participation-cooldown"
          role="status"
          class="mt-4 text-stone-700"
        >
          {gettext(
            "Please wait one minute before requesting a new confirmation. Your details are still here."
          )}
        </p>
        <p
          :if={@state == :delivery_error}
          id="account-email-error"
          role="alert"
          class="mt-4 text-red-800"
        >
          {gettext(
            "We could not send your confirmation. Your details are still here. Please try again."
          )}
        </p>
        <p :if={@intent in ["account", "action"]} class="mt-5 text-sm">
          <.link
            href={~p"/act/sign?locale=#{@locale}"}
            target="_blank"
            rel="noopener noreferrer"
            class="underline"
          >{gettext("Sign the PauseAI statement")}</.link>
          ·
          <.link
            href={~p"/act/actions?locale=#{@locale}"}
            target="_blank"
            rel="noopener noreferrer"
            class="underline"
          >{gettext("More ways to act")}</.link>
        </p>
        <p :if={@intent != "mp"} class="mt-6 text-sm text-stone-600">
          <.link
            href={
              if(@locale == "fr",
                do: ~p"/fr/contacter-votre-depute",
                else: ~p"/en/contact-your-mp"
              )
            }
            class="underline"
          >{gettext("Email your MP")}</.link>
          ·
          <a href="https://luma.com/calendar/cal-tsYv79s4aTQC16Q" class="underline">{gettext(
            "Upcoming events"
          )}</a>
        </p>
      </div>
    </section>
    """
  end
end
