defmodule PauseAiCaWeb.ProfileLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.{Accounts, Campaigns}

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
     |> assign_profile_form(user)
     |> assign(:resource_form, to_form(%{"url" => ""}, as: "resource"))}
  end

  @impl true
  def handle_event("save-profile", %{"profile" => params}, socket) do
    changeset = Accounts.change_user_profile(socket.assigns.profile_user, params)

    with {:ok, candidate} <- Ecto.Changeset.apply_action(changeset, :update),
         {:ok, [representative | _]} <-
           Campaigns.find_members_of_parliament(candidate.postal_code),
         {:ok, user} <-
           Accounts.update_user_profile(
             socket.assigns.profile_user,
             params,
             representative_map(representative)
           ) do
      {:noreply,
       socket
       |> assign(:profile_user, user)
       |> assign_profile_form(user)
       |> put_flash(
         :info,
         gettext("Profile saved.")
       )}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, as: "profile"))}

      {:ok, []} ->
        {:noreply, put_flash(socket, :error, lookup_error(:not_found, socket.assigns.locale))}

      {:error, reason} when reason in [:invalid_postal_code, :not_found, :unavailable] ->
        {:noreply, put_flash(socket, :error, lookup_error(reason, socket.assigns.locale))}
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

  defp assign_profile_form(socket, user) do
    assign(socket, :profile_form, to_form(Accounts.change_user_profile(user), as: "profile"))
  end

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

  defp lookup_error(:invalid_postal_code, _),
    do: gettext("Enter a complete Canadian postal code.")

  defp lookup_error(:not_found, _),
    do: gettext("No federal MP was found for that postal code.")

  defp lookup_error(:unavailable, _), do: gettext("The MP lookup is temporarily unavailable.")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={if(@locale == "fr", do: ~p"/en/profile", else: ~p"/fr/profil")}
    >
      <section id="profile" class="mx-auto max-w-4xl px-5 py-12 sm:py-20">
        <h1 class="font-serif text-5xl text-stone-950">
          {gettext("My profile")}
        </h1>

        <div class="mt-10 grid gap-8 lg:grid-cols-2">
          <section class="rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <h2 class="font-serif text-3xl text-stone-950">
              {gettext("My riding")}
            </h2>
            <.form
              for={@profile_form}
              id="profile-form"
              phx-submit="save-profile"
              class="mt-5 space-y-5"
            >
              <.input
                field={@profile_form[:postal_code]}
                type="text"
                label={gettext("Full postal code")}
                placeholder="H2X 1Y4"
                autocomplete="postal-code"
                class="w-full input bg-white text-stone-950 uppercase placeholder:text-stone-400"
              />
              <.input
                field={@profile_form[:city]}
                type="text"
                label={gettext("City (optional)")}
                autocomplete="address-level2"
              />
              <.input
                field={@profile_form[:local_updates]}
                type="checkbox"
                label={gettext("Send me relevant local updates")}
              />
              <button class="rounded-full bg-stone-900 px-5 py-3 font-semibold text-white">
                {gettext("Find my MP")}
              </button>
            </.form>

            <div
              :if={@profile_user.representative}
              id="mp-result"
              class="mt-6 border-t border-stone-200 pt-5"
            >
              <p class="font-heading text-xl font-bold text-stone-950">
                {@profile_user.representative["name"]}
              </p>
              <p class="text-stone-600">{@profile_user.representative["district"]}</p>
              <p class="text-sm text-stone-500">{@profile_user.representative["party"]}</p>
              <p id="mp-position" class="mt-4 rounded-2xl bg-stone-100 p-4 text-sm text-stone-700">
                {gettext("Position on pausing advanced AI: not yet documented by PauseAI Canada.")}
              </p>
            </div>
          </section>

          <section class="rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <h2 class="font-serif text-3xl text-stone-950">
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
      </section>
    </Layouts.app>
    """
  end

  defp resource_label("risk", _), do: gettext("Understand existential risk")
  defp resource_label("pause", _), do: gettext("Understand a pause")
  defp resource_label("coordination", _), do: gettext("Test coordination")
  defp resource_label("agency", _), do: gettext("Move toward action")
end
