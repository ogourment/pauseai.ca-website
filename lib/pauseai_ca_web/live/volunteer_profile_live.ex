defmodule PauseAiCaWeb.VolunteerProfileLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Volunteers
  alias PauseAiCa.Volunteers.Input
  alias PauseAiCaWeb.{ProfileComponents, VolunteerForms}

  @impl true
  def mount(_params, _, socket) do
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"
    Gettext.put_locale(PauseAiCaWeb.Gettext, locale)
    scope = socket.assigns.current_scope
    profile = Volunteers.get_profile(scope)
    values = Input.contribution_draft(profile.details, profile.draft)

    if connected?(socket), do: Process.send_after(self(), :refresh_group_work, 30_000)

    {:ok,
     assign(socket,
       locale: locale,
       page_title: gettext("Volunteer profile"),
       group_work: Volunteers.my_group_work(scope),
       has_location?: Enum.any?([scope.user.fsa, scope.user.postal_code], &(&1 not in [nil, ""])),
       values: values,
       saved_values: Input.contribution_values(values),
       errors: %{},
       save_state: :ready,
       form: to_form(values, as: "profile")
     )}
  end

  @impl true
  def handle_info(:refresh_group_work, socket) do
    Process.send_after(self(), :refresh_group_work, 30_000)

    {:noreply,
     assign(socket, :group_work, Volunteers.my_group_work(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("change", %{"profile" => attrs}, socket), do: change(socket, attrs)

  def handle_event("restore-draft", %{"values" => attrs}, socket) when is_map(attrs),
    do: change(socket, attrs)

  def handle_event("save", %{"profile" => attrs}, socket) do
    attrs = Map.take(attrs, Input.contribution_fields())
    values = Input.merge_profile(socket.assigns.values, attrs)

    edited =
      values
      |> Input.contribution_values()
      |> Map.take(Map.keys(attrs))
      |> Map.reject(fn {key, value} -> socket.assigns.saved_values[key] == value end)

    case Volunteers.save_contribution(socket.assigns.current_scope, edited) do
      {:ok, profile} ->
        persisted = Input.contribution_draft(profile.details, profile.draft)

        {:noreply,
         socket
         |> assign(:saved_values, Input.contribution_values(persisted))
         |> set_values(persisted, :saved, %{})}

      {:error, errors} when is_map(errors) and not is_struct(errors) ->
        {:noreply, set_values(socket, values, :invalid, errors)}

      {:error, _} ->
        {:noreply, set_values(socket, values, :failed, socket.assigns.errors)}
    end
  end

  defp change(socket, attrs) do
    values =
      Input.merge_profile(socket.assigns.values, Map.take(attrs, Input.contribution_fields()))

    errors = Map.take(Input.profile_errors(values), Map.keys(socket.assigns.errors))
    {:noreply, set_values(socket, values, :dirty, errors)}
  end

  defp set_values(socket, values, state, errors) do
    assign(socket,
      values: values,
      errors: errors,
      save_state: state,
      form: to_form(values, as: "profile")
    )
  end

  defp save_status(:saved), do: gettext("Saved")
  defp save_status(:dirty), do: gettext("Unsaved changes")
  defp save_status(:invalid), do: gettext("Check the highlighted fields and save again.")
  defp save_status(:failed), do: gettext("Your changes could not be saved. Please try again.")
  defp save_status(:ready), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      promote_warning_shot={false}
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      breadcrumb_context={PauseAiCaWeb.Navigation.profile_breadcrumb_context(@locale)}
      breadcrumb_scope={"volunteer_profile:" <> @locale}
      translated_path={
        if @locale == "fr", do: ~p"/en/profile/volunteer", else: ~p"/fr/profil/benevolat"
      }
    >
      <section
        class={["mx-auto max-w-4xl space-y-5 px-5 py-12", ProfileComponents.form_styles()]}
        id="volunteer-profile"
        lang={@locale}
      >
        <ProfileComponents.profile_navigation locale={@locale} current={:volunteer} />
        <h1 class="text-balance font-serif text-5xl text-stone-950">
          {gettext("Volunteer profile")}
        </h1>
        <section
          :if={@group_work.roles != [] or @group_work.tasks != []}
          id="my-group-work"
          class="rounded-xl border border-stone-200 bg-stone-100 p-5"
          aria-labelledby="volunteer-group-work-title"
        >
          <h2 id="volunteer-group-work-title" class="font-serif text-2xl">
            {gettext("My group work")}
          </h2>
          <h3 :if={@group_work.roles != []} class="mt-3 font-semibold">{gettext("My roles")}</h3>
          <ul :if={@group_work.roles != []}>
            <li :for={r <- @group_work.roles}>{r.title} · {r.group}</li>
          </ul>
          <h3 :if={@group_work.tasks != []} class="mt-3 font-semibold">
            {gettext("Assigned to me")}
          </h3>
          <ul :if={@group_work.tasks != []} class="space-y-3">
            <li :for={t <- @group_work.tasks}>
              <p><strong>{t.title}</strong> · {t.group}</p>
              <p class="text-sm">{PauseAiCaWeb.TasksLive.status(t.status)}</p>
              <p :if={t.description} class="whitespace-pre-line">{t.description}</p>
              <p :if={t.due_date}>
                {gettext("Due date")} ·
                <time datetime={Date.to_iso8601(t.due_date)}>{t.due_date}</time>
              </p>
            </li>
          </ul>
        </section>
        <aside
          :if={!@has_location?}
          id="volunteer-location-reminder"
          class="space-y-1 rounded-xl border border-stone-200 bg-stone-100 p-4"
        >
          <p>
            {gettext(
              "Add an optional postal code or prefix to help identify volunteer opportunities near you."
            )}
          </p>
          <.link href={ProfileComponents.personal_path(@locale) <> "#location"} class="underline">{gettext(
            "Edit my location"
          )}</.link>
        </aside>
        <.form
          for={@form}
          phx-change="change"
          phx-submit="save"
          id="volunteer-profile-form"
          phx-hook="FormDraft"
          data-draft-prefix="profile"
          data-draft-key={"pauseai:volunteer:" <> @current_scope.user.id}
          data-draft-clear-on-save="true"
          data-submitted={to_string(@save_state == :saved)}
        >
          <fieldset
            disabled={!connected?(@socket)}
            class="grid min-w-0 items-start gap-4 md:grid-cols-2"
          >
            <VolunteerForms.contribution_fields form={@form} errors={@errors}>
              <div class="flex flex-wrap items-center gap-3">
                <button
                  type="submit"
                  class={ProfileComponents.action_class()}
                  phx-disable-with={gettext("Saving…")}
                >
                  {gettext("Save changes")}
                </button>
                <p id="volunteer-save-status" role="status">{save_status(@save_state)}</p>
              </div>
            </VolunteerForms.contribution_fields>
          </fieldset>
        </.form>
        <.link href={ProfileComponents.personal_path(@locale) <> "#identity-title"} class="underline">
          {gettext("Edit my contact details")}
        </.link>
      </section>
    </Layouts.app>
    """
  end
end
