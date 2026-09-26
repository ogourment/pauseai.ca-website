defmodule PauseAiCaWeb.VolunteerProfileLive do
  use PauseAiCaWeb, :live_view
  alias PauseAiCa.Volunteers
  alias PauseAiCaWeb.VolunteerForms

  @impl true
  def mount(params, _, socket) do
    locale = if params["locale"] == "fr", do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    socket = assign(socket, :locale, locale)
    profile = Volunteers.get_profile(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: gettext("Volunteer profile"),
       profile: profile,
       step: profile.step,
       values: profile.draft,
       errors: %{},
       saved?: true,
       form: to_form(profile.draft, as: "profile")
     )}
  end

  @impl true
  def handle_event("change", %{"profile" => attrs}, socket) do
    values = Map.merge(socket.assigns.values, attrs)

    {:noreply,
     assign(socket, values: values, saved?: false, form: to_form(values, as: "profile"))}
  end

  def handle_event("save", %{"profile" => attrs}, socket) do
    {:noreply, saved} =
      save(socket, Map.merge(socket.assigns.values, attrs), socket.assigns.step, false)

    {:noreply,
     if(saved.assigns.saved?, do: push_navigate(saved, to: ~p"/dashboard"), else: saved)}
  end

  def handle_event("save", _, socket),
    do: save(socket, socket.assigns.values, socket.assigns.step, false)

  def handle_event("next", _, socket),
    do:
      save(
        socket,
        socket.assigns.values,
        if(socket.assigns.step == "contact", do: "contribution", else: "review"),
        false
      )

  def handle_event("back", _, socket),
    do:
      {:noreply,
       assign(
         socket,
         :step,
         if(socket.assigns.step == "review", do: "contribution", else: "contact")
       )}

  def handle_event("publish", _, socket), do: save(socket, socket.assigns.values, "review", true)

  defp save(socket, values, step, publish?) do
    case Volunteers.save_profile(socket.assigns.current_scope, values, step, publish?) do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(
           profile: profile,
           values: profile.draft,
           step: step,
           errors: %{},
           saved?: true,
           form: to_form(profile.draft, as: "profile")
         )
         |> put_flash(
           :info,
           if(publish?,
             do: gettext("Profile saved."),
             else: gettext("Draft saved. You can resume after signing in.")
           )
         )}

      {:error, errors} ->
        {:noreply,
         socket
         |> assign(
           errors: if(is_map(errors) and not is_struct(errors), do: errors, else: %{}),
           saved?: false
         )
         |> put_flash(:error, gettext("Check the fields. Your changes are still here."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      promote_warning_shot={false}
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={~p"/volunteer-profile?locale=#{if(@locale == "fr", do: "en", else: "fr")}"}
    >
      <section class="mx-auto max-w-3xl space-y-5 px-5 py-12" id="volunteer-profile" lang={@locale}>
        <h1 class="text-4xl font-bold">{gettext("Volunteer profile")}</h1>
        <p>
          {gettext("Share what helps us organize together. Optional details can be completed later.")}
        </p>
        <p>{gettext("Contact → Contribution → Review")}</p>
        <.form
          for={@form}
          phx-change="change"
          phx-submit="save"
          id="volunteer-profile-form"
          class="space-y-5 rounded-xl border bg-white p-6"
        >
          <%= if @step == "review" do %>
            <dl>
              <div :for={{key, value} <- @values} :if={value != ""} class="mb-3">
                <dt class="font-semibold">{VolunteerForms.label(key)}</dt><dd class="whitespace-pre-wrap">
                  {value}
                </dd>
              </div>
            </dl>
          <% else %>
            <VolunteerForms.profile_fields form={@form} step={@step} errors={@errors} />
          <% end %>
          <p :for={{field, reason} <- @errors} class="text-red-700" role="alert">
            {VolunteerForms.label(field)}: {VolunteerForms.error(reason)}
          </p>
          <div class="flex flex-wrap gap-3">
            <.button>{gettext("Save and exit")}</.button><.button
              :if={@step != "review"}
              type="button"
              phx-click="next"
            >{gettext("Next")}</.button><.button
              :if={@step == "review"}
              type="button"
              phx-click="publish"
            >{gettext("Save profile")}</.button><button
              :if={@step != "contact"}
              type="button"
              phx-click="back"
              class="underline"
            >{gettext("Back")}</button>
          </div>
          <p role="status">
            {if @saved?, do: gettext("Saved"), else: gettext("Unsaved changes — save before leaving")}
          </p>
        </.form>
        <.link
          navigate={if @locale == "fr", do: ~p"/fr/profil", else: ~p"/en/profile"}
          class="underline"
        >{gettext("My profile")}</.link>
      </section>
    </Layouts.app>
    """
  end
end
