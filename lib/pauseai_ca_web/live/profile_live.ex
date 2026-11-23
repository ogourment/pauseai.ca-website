defmodule PauseAiCaWeb.ProfileLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.{Accounts, Campaigns, PostalArea}
  alias PauseAiCa.Accounts.PersonalProfile

  @impl true
  def mount(_params, _session, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:locale, locale)
     |> assign(:page_title, gettext("My profile"))
     |> assign(:profile_user, user)
     |> assign(profile_saved?: false, contact_open?: false)
     |> assign_profile_form(user)
     |> assign_lookup(user)
     |> assign(:resource_form, to_form(%{"url" => ""}, as: "resource"))}
  end

  @impl true
  def handle_event("change-profile", %{"profile" => params}, socket),
    do: edit_profile(socket, params)

  def handle_event("restore-draft", %{"values" => params}, socket) when is_map(params),
    do: edit_profile(socket, params)

  def handle_event("save-profile", %{"profile" => params}, socket) do
    previous = socket.assigns.profile_user

    case PersonalProfile.update(previous, socket.assigns.profile_values, params) do
      {:ok, user} ->
        socket =
          socket
          |> assign(profile_user: user, profile_saved?: true)
          |> assign_profile_form(user)

        socket =
          if {user.postal_code, user.fsa} == {previous.postal_code, previous.fsa} do
            socket
          else
            socket |> cancel_async(:mp_lookup) |> assign_lookup(user)
          end

        {:noreply, socket}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_profile_errors(socket, changeset)}
    end
  end

  def handle_event("lookup-mp", %{"lookup" => %{"postal_code" => input}}, socket)
      when is_binary(input) do
    postal_code = PostalArea.normalize(input)

    socket =
      socket
      |> cancel_async(:mp_lookup)
      |> assign(
        lookup_open?: true,
        lookup_error: nil,
        lookup_form: lookup_form(input),
        lookup_result: nil,
        lookup_loading?: false
      )

    if PersonalProfile.full_postal?(postal_code) do
      {:noreply,
       socket
       |> assign(
         lookup_loading?: true,
         lookup_form: lookup_form(PersonalProfile.display_postal(postal_code))
       )
       |> start_async(:mp_lookup, fn ->
         {postal_code, Campaigns.find_members_of_parliament(postal_code)}
       end)}
    else
      {:noreply, assign(socket, :lookup_error, lookup_error(:invalid_postal_code))}
    end
  end

  def handle_event("add-resource", %{"resource" => %{"url" => url}}, socket) do
    case Accounts.add_custom_resource(socket.assigns.profile_user, String.trim(url)) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:profile_user, user)
         |> assign(:resource_form, to_form(%{"url" => ""}, as: "resource"))}

      {:error, :invalid_url} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Enter a complete web address.")
         )}
    end
  end

  def handle_event("remove-saved-resource", %{"resource" => resource}, socket) do
    {:ok, user} = Accounts.remove_saved_resource(socket.assigns.profile_user, resource)
    {:noreply, assign(socket, :profile_user, user)}
  end

  def handle_event("remove-custom-resource", %{"url" => url}, socket) do
    {:ok, user} = Accounts.remove_custom_resource(socket.assigns.profile_user, url)
    {:noreply, assign(socket, :profile_user, user)}
  end

  @impl true
  def handle_async(:mp_lookup, {:ok, {postal_code, {:ok, [representative | _]}}}, socket) do
    result = representative_map(representative)
    user = PersonalProfile.cache_representative(socket.assigns.profile_user, postal_code, result)

    {:noreply, assign(socket, profile_user: user, lookup_loading?: false, lookup_result: result)}
  end

  def handle_async(:mp_lookup, {:ok, {_postal_code, {:ok, []}}}, socket),
    do: lookup_failed(socket, :not_found)

  def handle_async(:mp_lookup, {:ok, {_postal_code, {:error, reason}}}, socket),
    do: lookup_failed(socket, reason)

  def handle_async(:mp_lookup, {:exit, _reason}, socket) do
    if socket.assigns.lookup_loading?,
      do: lookup_failed(socket, :unavailable),
      else: {:noreply, socket}
  end

  defp edit_profile(socket, params) do
    changeset = PersonalProfile.change(socket.assigns.profile_values, params)
    {:noreply, assign_profile_errors(socket, %{changeset | action: :validate})}
  end

  defp assign_profile_errors(socket, changeset) do
    contact_fields = [:discord_handle, :signal_number, :whatsapp_number, :contact_notes]
    contact_error? = Enum.any?(contact_fields, &Keyword.has_key?(changeset.errors, &1))

    assign(socket,
      profile_form: to_form(changeset, as: "profile"),
      profile_saved?: false,
      contact_open?: socket.assigns.contact_open? || contact_error?
    )
  end

  defp lookup_failed(socket, reason),
    do: {:noreply, assign(socket, lookup_loading?: false, lookup_error: lookup_error(reason))}

  defp assign_profile_form(socket, user) do
    {values, city_conflict} = PersonalProfile.editor(user)

    assign(socket,
      profile_values: values,
      profile_form: to_form(PersonalProfile.change(values), as: "profile"),
      city_conflict: Enum.join(city_conflict, ", ")
    )
  end

  defp assign_lookup(socket, user) do
    assign(socket,
      lookup_open?: not is_nil(user.representative),
      lookup_form: lookup_form(PersonalProfile.display_postal(user.postal_code)),
      lookup_error: nil,
      lookup_loading?: false,
      lookup_result: user.representative
    )
  end

  defp contact_options(previous) do
    options = [
      {gettext("Email"), "email"},
      {"Discord", "discord"},
      {"Signal", "signal"},
      {"WhatsApp", "whatsapp"}
    ]

    if previous && previous not in Enum.map(options, &elem(&1, 1)),
      do: options ++ [{previous, previous}],
      else: options
  end

  defp lookup_form(postal_code), do: to_form(%{"postal_code" => postal_code}, as: "lookup")

  defp representative_map(representative) do
    %{
      "name" => representative.name,
      "district" => representative.district,
      "party" => representative.party,
      "email" => representative.email,
      "profile_url" => representative.profile_url,
      "position" => "undocumented"
    }
  end

  defp lookup_error(:invalid_postal_code),
    do: gettext("Enter a complete Canadian postal code.")

  defp lookup_error(:not_found),
    do: gettext("No federal MP was found for that postal code.")

  defp lookup_error(:unavailable), do: gettext("The MP lookup is temporarily unavailable.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      promote_warning_shot={false}
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      breadcrumb_context={PauseAiCaWeb.Navigation.profile_breadcrumb_context(@locale)}
      breadcrumb_scope={"profile:" <> @locale}
      translated_path={if(@locale == "fr", do: ~p"/en/profile", else: ~p"/fr/profil")}
    >
      <section
        id="profile"
        class={[
          "mx-auto max-w-4xl px-5 py-12 sm:py-20",
          PauseAiCaWeb.ProfileComponents.form_styles()
        ]}
      >
        <PauseAiCaWeb.ProfileComponents.profile_navigation locale={@locale} current={:personal} />
        <h1 class="mt-3 font-serif text-5xl text-stone-950">
          {gettext("My profile")}
        </h1>

        <div class="mt-6 grid items-start gap-6 lg:grid-cols-[3fr_2fr]">
          <.form
            for={@profile_form}
            id="profile-form"
            phx-hook="FormDraft"
            data-draft-prefix="profile"
            data-draft-key={"pauseai:profile:" <> @profile_user.id}
            data-draft-clear-on-save="true"
            data-submitted={to_string(@profile_saved?)}
            phx-change="change-profile"
            phx-submit="save-profile"
            class="space-y-6 rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6"
          >
            <section aria-labelledby="identity-title">
              <h2 id="identity-title" class="mb-4 text-balance font-serif text-3xl">
                {gettext("Contact details")}
              </h2>
              <div class="grid gap-4 sm:grid-cols-2">
                <.input
                  field={@profile_form[:name]}
                  type="text"
                  label={gettext("Name")}
                  autocomplete="name"
                />
                <.input
                  id="profile-account-email"
                  name="account-email"
                  type="email"
                  label={gettext("Account email")}
                  value={@profile_user.email}
                  readonly
                />
                <.input
                  field={@profile_form[:phone]}
                  type="tel"
                  label={gettext("Phone (optional)")}
                  autocomplete="tel"
                  maxlength="40"
                />
                <.input
                  field={@profile_form[:contact_preference]}
                  type="select"
                  label={gettext("Preferred contact method")}
                  prompt={gettext("Not specified")}
                  options={contact_options(@profile_values.contact_preference)}
                />
                <details
                  class="rounded-xl border border-stone-200 p-3 sm:col-span-2"
                  open={@contact_open?}
                >
                  <summary class="cursor-pointer font-semibold">
                    {gettext("Other ways to reach me")}
                  </summary>
                  <div class="mt-4 grid gap-4 sm:grid-cols-2">
                    <.input field={@profile_form[:discord_handle]} type="text" label="Discord" />
                    <.input field={@profile_form[:signal_number]} type="tel" label="Signal" />
                    <.input field={@profile_form[:whatsapp_number]} type="tel" label="WhatsApp" />
                    <div class="sm:col-span-2">
                      <.input
                        field={@profile_form[:contact_notes]}
                        type="textarea"
                        label={gettext("Contact instructions")}
                      />
                    </div>
                  </div>
                </details>
              </div>
            </section>
            <section
              id="location"
              tabindex="-1"
              class="scroll-mt-24 border-t border-stone-200 pt-5"
              aria-labelledby="profile-location-title"
            >
              <h2 id="profile-location-title" class="mb-4 text-balance font-serif text-3xl">
                {gettext("Location and local updates")}
              </h2>
              <div class="grid gap-4 sm:grid-cols-2">
                <.input
                  field={@profile_form[:city]}
                  type="text"
                  label={gettext("City")}
                  autocomplete="address-level2"
                />
                <.input
                  field={@profile_form[:country]}
                  type="text"
                  label={gettext("Country")}
                  autocomplete="country-name"
                />
                <div
                  :if={@city_conflict != ""}
                  id="profile-city-conflict"
                  class="rounded-xl bg-stone-100 p-3 sm:col-span-2"
                >
                  <p>
                    {gettext(
                      "Your previous volunteer profile lists %{city}. Enter the city you want to keep.",
                      city: @city_conflict
                    )}
                  </p>
                  <.input
                    field={@profile_form[:confirm_city]}
                    type="checkbox"
                    label={gettext("Use the city entered above")}
                  />
                </div>
                <div class="sm:col-span-2">
                  <.input
                    field={@profile_form[:postal_code]}
                    type="text"
                    label={gettext("Postal code (optional)")}
                    placeholder="H2X"
                    autocomplete="postal-code"
                    aria-describedby="profile-postal-help"
                  />
                  <p id="profile-postal-help" class="mt-1 text-sm text-pretty text-stone-600">
                    {gettext(
                      "Enter the first three characters (H2X) or the full postal code (H2X 1Y4)."
                    )}
                  </p>
                </div>
                <div class="sm:col-span-2">
                  <.input
                    field={@profile_form[:local_updates]}
                    type="checkbox"
                    label={gettext("Send me relevant local updates")}
                  />
                </div>
              </div>
            </section>
            <div class="flex flex-wrap items-center gap-3">
              <.button class={PauseAiCaWeb.ProfileComponents.action_class()}>{gettext("Save changes")}</.button>
              <p id="profile-save-status" class="text-sm text-stone-700" role="status">
                {if @profile_saved?, do: gettext("Profile saved.")}
              </p>
            </div>
          </.form>

          <div class="space-y-6">
            <details
              id="mp-lookup"
              open={@lookup_open?}
              class="rounded-3xl border border-stone-200 bg-white p-5 shadow-sm sm:p-6"
            >
              <summary class="cursor-pointer text-balance font-serif text-3xl">
                {gettext("Find my MP")}
              </summary>
              <p class="mt-3 text-stone-600">
                {gettext(
                  "Look up your federal riding and member of Parliament using a full Canadian postal code."
                )}
              </p>
              <.form for={@lookup_form} id="mp-form" phx-submit="lookup-mp" class="mt-4 space-y-3">
                <.input
                  field={@lookup_form[:postal_code]}
                  type="text"
                  label={gettext("Full postal code")}
                  placeholder="H2X 1Y4"
                  autocomplete="postal-code"
                  aria-invalid={not is_nil(@lookup_error)}
                  aria-describedby={if @lookup_error, do: "mp-lookup-error"}
                />
                <p :if={@lookup_error} id="mp-lookup-error" role="alert" class="text-sm text-red-700">
                  {@lookup_error}
                </p>
                <.button
                  class={PauseAiCaWeb.ProfileComponents.action_class()}
                  disabled={@lookup_loading?}
                >{gettext("Look up my MP")}</.button>
              </.form>
              <p :if={@lookup_loading?} class="mt-3 text-sm" role="status">
                {gettext("Looking up your MP…")}
              </p>
              <div
                :if={@lookup_result}
                id="mp-result"
                class="mt-5 border-t border-stone-200 pt-4"
                role="status"
              >
                <p class="font-heading text-xl font-bold text-stone-950">
                  {@lookup_result["name"]}
                </p>
                <p class="text-stone-600">{@lookup_result["district"]}</p>
                <p class="text-sm text-stone-500">{@lookup_result["party"]}</p>
                <p id="mp-position" class="mt-4 rounded-2xl bg-stone-100 p-4 text-sm text-stone-700">
                  {gettext("Position on pausing advanced AI: not yet documented by PauseAI Canada.")}
                </p>
              </div>
            </details>

            <section class="rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
              <h2 class="text-balance font-serif text-3xl text-stone-950">
                {gettext("My learning path")}
              </h2>
              <ul id="profile-saved-resources" class="mt-5 space-y-3">
                <li
                  :for={resource <- @profile_user.saved_resources}
                  class="flex items-center justify-between gap-3"
                >
                  <span>{resource_label(resource, @locale)}</span>
                  <button
                    type="button"
                    phx-click="remove-saved-resource"
                    phx-value-resource={resource}
                    class="text-sm underline"
                  >
                    {gettext("Remove")}
                  </button>
                </li>
              </ul>

              <.form
                for={@resource_form}
                id="custom-resource-form"
                phx-submit="add-resource"
                class="mt-6 space-y-3 border-t border-stone-200 pt-5"
              >
                <.input
                  field={@resource_form[:url]}
                  type="url"
                  label={gettext("Add a resource")}
                  placeholder="https://…"
                />
                <button class="rounded-full border border-stone-300 px-4 py-2 font-semibold">
                  {gettext("Add")}
                </button>
              </.form>
              <ul id="custom-resources" class="mt-5 space-y-3">
                <li
                  :for={url <- @profile_user.custom_resource_urls}
                  class="flex items-center justify-between gap-3"
                >
                  <a href={url} class="min-w-0 truncate underline" target="_blank" rel="noreferrer">{url}</a>
                  <button
                    type="button"
                    phx-click="remove-custom-resource"
                    phx-value-url={url}
                    class="text-sm underline"
                  >
                    {gettext("Remove")}
                  </button>
                </li>
              </ul>
            </section>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp resource_label("risk", _), do: gettext("Understand existential risk")
  defp resource_label("pause", _), do: gettext("Understand a pause")
  defp resource_label("coordination", _), do: gettext("Test coordination")
  defp resource_label("agency", _), do: gettext("Move toward action")

  defp resource_label(resource, locale) do
    resource
    |> PauseAiCa.Library.resource()
    |> PauseAiCa.Library.Resource.copy(locale)
    |> Map.fetch!(:title)
  end
end
