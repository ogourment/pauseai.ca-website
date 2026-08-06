defmodule PauseAiCaWeb.DashboardLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Engagement
  alias PauseAiCa.Engagement.Action
  alias PauseAiCa.Engagement.Ladder

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    actions = Engagement.list_actions(scope)
    confirmed_actions = Enum.reject(actions, &Action.pending?/1)
    locale = if socket.assigns.live_action == :fr, do: "fr", else: "en"

    {:ok,
     socket
     |> assign(:locale, locale)
     |> assign(:page_title, gettext("My dashboard"))
     |> assign(
       :recommendation,
       Ladder.recommendation(confirmed_actions, locale)
     )
     |> assign(:ladder_position, Ladder.position(confirmed_actions))
     |> assign(:action_count, Enum.count(actions, &(not Action.pending?(&1))))
     |> assign(:pending, Engagement.list_pending_actions(scope))
     |> assign(:editing_id, nil)
     |> assign(:selected_type, nil)
     |> assign(:needs_local_context, is_nil(scope.user.postal_code))
     |> assign(:representative, scope.user.representative)
     |> assign(:saved_resources, scope.user.saved_resources)
     |> assign(:custom_resource_urls, scope.user.custom_resource_urls)
     |> assign_form(Engagement.new_action(scope))
     |> stream(:actions, Enum.reject(actions, &Action.pending?/1))}
  end

  @impl true
  def handle_event("validate", %{"action" => params}, socket) do
    changeset =
      socket.assigns.current_scope
      |> Engagement.change_action(form_action(socket), params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:selected_type, params["action_type"])}
  end

  def handle_event("save", %{"action" => params}, socket) do
    if socket.assigns.editing_id do
      update_action(socket, params)
    else
      create_action(socket, params)
    end
  end

  def handle_event("confirm-action", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    action = Engagement.get_action!(scope, id)
    {:ok, action} = Engagement.confirm_action(scope, action)

    {:noreply,
     socket
     |> assign(:pending, Engagement.list_pending_actions(scope))
     |> assign(:action_count, socket.assigns.action_count + 1)
     |> stream_insert(:actions, action)
     |> refresh_recommendation()
     |> put_flash(:info, "Recorded. Thank you for following through.")}
  end

  def handle_event("discard-action", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope
    action = Engagement.get_action!(scope, id)
    {:ok, _deleted} = Engagement.delete_action(scope, action)

    {:noreply,
     socket
     |> assign(:pending, Engagement.list_pending_actions(scope))
     |> stream_delete(:actions, action)
     |> put_flash(:info, "Removed. Nothing recorded.")}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    action = Engagement.get_action!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:editing_id, action.id)
     |> assign(:selected_type, action.action_type)
     |> assign_form(action)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_id, nil)
     |> assign(:selected_type, nil)
     |> assign_form(Engagement.new_action(socket.assigns.current_scope))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    action = Engagement.get_action!(socket.assigns.current_scope, id)
    {:ok, _action} = Engagement.delete_action(socket.assigns.current_scope, action)

    {:noreply,
     socket
     |> update(:action_count, &max(&1 - 1, 0))
     |> stream_delete(:actions, action)
     |> refresh_recommendation()}
  end

  defp create_action(socket, params) do
    # Submitting this journal form is the user's direct statement that the
    # action happened. Pending actions are reserved for external handoffs,
    # where opening a mail app or form does not prove completion.
    params =
      Map.put(params, "confirmed_at", DateTime.utc_now() |> DateTime.truncate(:second))

    case Engagement.create_action(socket.assigns.current_scope, params) do
      {:ok, action} ->
        {:noreply,
         socket
         |> put_flash(:info, "Action recorded privately.")
         |> update(:action_count, &(&1 + 1))
         |> stream_insert(:actions, action, at: 0)
         |> assign_form(Engagement.new_action(socket.assigns.current_scope))
         |> refresh_recommendation()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp update_action(socket, params) do
    action = Engagement.get_action!(socket.assigns.current_scope, socket.assigns.editing_id)

    case Engagement.update_action(socket.assigns.current_scope, action, params) do
      {:ok, action} ->
        {:noreply,
         socket
         |> put_flash(:info, "Action updated.")
         |> assign(:editing_id, nil)
         |> assign(:selected_type, nil)
         |> stream_insert(:actions, action)
         |> assign_form(Engagement.new_action(socket.assigns.current_scope))
         |> refresh_recommendation()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp form_action(socket) do
    case socket.assigns.editing_id do
      nil -> Engagement.new_action(socket.assigns.current_scope)
      id -> Engagement.get_action!(socket.assigns.current_scope, id)
    end
  end

  defp assign_form(socket, %Action{} = action) do
    changeset = Engagement.change_action(socket.assigns.current_scope, action)
    assign(socket, :form, to_form(changeset))
  end

  defp refresh_recommendation(socket) do
    actions =
      socket.assigns.current_scope
      |> Engagement.list_actions()
      |> Enum.reject(&Action.pending?/1)

    socket
    |> assign(:recommendation, Ladder.recommendation(actions, socket.assigns.locale))
    |> assign(:ladder_position, Ladder.position(actions))
  end

  defp unit("flyered"), do: "handed out"
  defp unit("conversation"), do: "people"
  defp unit(_type), do: "people"

  # What a number means depends entirely on what was done.
  defp quantity_label("event"), do: "Roughly how many people were there?"
  defp quantity_label("organized"), do: "Roughly how many people came?"
  defp quantity_label("flyered"), do: "Roughly how many did you hand out or put up?"
  defp quantity_label("conversation"), do: "How many people did you talk with?"
  defp quantity_label(_type), do: "How many?"

  defp format_date(%Date{} = date, "fr") do
    months =
      ~w(janvier février mars avril mai juin juillet août septembre octobre novembre décembre)

    "#{date.day} #{Enum.at(months, date.month - 1)} #{date.year}"
  end

  defp format_date(%Date{} = date, _locale) do
    months =
      ~w(January February March April May June July August September October November December)

    "#{Enum.at(months, date.month - 1)} #{date.day}, #{date.year}"
  end

  defp saved_resource_url("risk", "fr"),
    do:
      "https://yoshuabengio.org/fr/blogue/questions-frequentes-sur-les-risques-catastrophiques-lies-lia"

  defp saved_resource_url("risk", _), do: "https://pauseai.info/xrisk"
  defp saved_resource_url("pause", "fr"), do: "https://pauseia.fr/propositions"
  defp saved_resource_url("pause", _), do: "https://pauseai.info/proposal"
  defp saved_resource_url("coordination", "fr"), do: "https://pauseia.fr/faq"
  defp saved_resource_url("coordination", _), do: "https://pauseai.info/feasibility"
  defp saved_resource_url("agency", "fr"), do: ~p"/fr/strategie"
  defp saved_resource_url("agency", _), do: ~p"/en/strategy"

  defp saved_resource_label("risk", _), do: gettext("Understand existential risk")
  defp saved_resource_label("pause", _), do: gettext("Understand a pause")
  defp saved_resource_label("coordination", _), do: gettext("Test coordination")
  defp saved_resource_label("agency", _), do: gettext("Move toward action")

  defp action_label("learned", _locale), do: gettext("Read or watched a resource")
  defp action_label("conversation", _), do: gettext("Discussed AI risk with someone")
  defp action_label("event", _), do: gettext("Attended an event")
  defp action_label("contacted_representative", _), do: gettext("Contacted a representative")
  defp action_label("met_representative", _), do: gettext("Met a representative")
  defp action_label("joined", _), do: gettext("Joined PauseAI")
  defp action_label("signed", _), do: gettext("Signed the PauseAI statement")
  defp action_label("flyered", _), do: gettext("Handed out flyers or put up posters")
  defp action_label("volunteered", _), do: gettext("Volunteered")
  defp action_label("organized", _), do: gettext("Organized an activity")
  defp action_label("other", _), do: gettext("Other private action")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={if(@locale == "fr", do: ~p"/en/dashboard", else: ~p"/fr/tableau-de-bord")}
    >
      <section class="mx-auto grid max-w-6xl gap-10 px-5 py-12 lg:grid-cols-[0.8fr_1.2fr] lg:py-20">
        <div>
          <p class="eyebrow">
            {gettext("Your private workspace")}
          </p>
          <h1 class="mt-3 font-serif text-5xl leading-tight text-stone-950">
            {gettext("My dashboard")}
          </h1>

          <div
            :if={@needs_local_context}
            id="fsa-reminder"
            class="mt-8 rounded-3xl border border-brand/40 bg-brand-wash p-6"
          >
            <h2 class="font-serif text-2xl text-stone-950">
              {gettext("Where does your MP stand?")}
            </h2>
            <p class="mt-2 leading-7 text-stone-600">
              {gettext("Add your full postal code to your profile to identify your riding and MP.")}
            </p>
            <.link
              navigate={if(@locale == "fr", do: ~p"/fr/profil", else: ~p"/en/profile")}
              class="mt-4 inline-flex rounded-full bg-stone-900 px-5 py-3 font-semibold text-white hover:bg-stone-700"
            >
              {gettext("Complete my profile")}
            </.link>
          </div>

          <div
            :if={@representative}
            id="dashboard-mp"
            class="mt-8 rounded-3xl border border-stone-200 bg-white p-6 shadow-sm"
          >
            <h2 class="font-serif text-2xl text-stone-950">
              {gettext("My MP")}
            </h2>
            <p class="mt-3 font-heading text-xl font-bold text-stone-950">
              {@representative["name"]}
            </p>
            <p class="text-stone-600">{@representative["district"]} · {@representative["party"]}</p>
            <p class="mt-3 text-sm text-stone-600">
              {gettext("Position on pausing advanced AI: not yet documented.")}
            </p>
            <.link
              navigate={if(@locale == "fr", do: ~p"/fr/profil", else: ~p"/en/profile")}
              class="mt-3 inline-block text-sm font-semibold underline"
            >
              {gettext("Edit my profile")}
            </.link>
          </div>
          <p class="mt-5 max-w-lg text-lg leading-8 text-stone-600">
            {gettext(
              "Your log is visible only to you. Only aggregate counts are used to understand movement progress."
            )}
          </p>

          <div
            :if={@saved_resources != [] or @custom_resource_urls != []}
            id="saved-resources"
            class="mt-8 rounded-3xl border border-stone-200 bg-white p-6 shadow-sm"
          >
            <h2 class="font-serif text-2xl text-stone-950">
              {gettext("Saved for later")}
            </h2>
            <ul class="mt-3 space-y-2">
              <li :for={resource <- @saved_resources}>
                <a
                  class="font-semibold text-stone-700 underline decoration-brand underline-offset-4"
                  href={saved_resource_url(resource, @locale)}
                >
                  {saved_resource_label(resource, @locale)}
                </a>
              </li>
              <li :for={url <- @custom_resource_urls}>
                <a
                  class="font-semibold text-stone-700 underline decoration-brand underline-offset-4"
                  href={url}
                  target="_blank"
                  rel="noreferrer"
                >
                  {url}
                </a>
              </li>
            </ul>
            <.link
              navigate={if(@locale == "fr", do: ~p"/fr/profil", else: ~p"/en/profile")}
              class="mt-4 inline-block text-sm font-semibold underline"
            >
              {gettext("Manage my learning path")}
            </.link>
          </div>

          <div class="mt-8 rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <p class="text-sm font-semibold uppercase tracking-widest text-brand-ink">
              {@action_count} {gettext("actions recorded")}
            </p>
            <h2 id="suggested-next-step" class="mt-3 font-heading text-2xl text-stone-950">
              {@recommendation.title}
            </h2>
            <p class="mt-2 text-stone-600">{@recommendation.why}</p>
            <p class="mt-3 text-sm text-stone-500">
              {gettext("Estimated time")}: {@recommendation.effort}
            </p>
            <.link
              href={@recommendation.href}
              class="mt-4 inline-flex rounded-full bg-brand px-5 py-2.5 font-semibold text-stone-950 hover:bg-brand-strong"
            >{@recommendation.cta}</.link>
          </div>

          <section
            id="engagement-ladder"
            class="mt-8 overflow-hidden rounded-3xl bg-stone-900 p-6 text-white"
          >
            <h2 class="font-heading text-2xl">
              {gettext("Other ways to act")}
            </h2>
            <p class="mt-2 text-sm leading-6 text-white/70">
              {gettext("Your suggested next step is only one option. Choose what fits you now.")}
            </p>
            <ol class="mt-6 flex flex-col-reverse px-2">
              <li
                :for={{step, i} <- Enum.with_index(Ladder.steps(@locale), 1)}
                id={"ladder-step-#{i}"}
                data-current={i == @ladder_position}
                class="relative border-x-[6px] border-white/30 px-4 pb-5"
              >
                <div class={[
                  "relative border-t-[6px] pt-3",
                  i == @ladder_position && "border-brand",
                  i != @ladder_position && "border-white/30"
                ]}>
                  <span
                    :if={i == @ladder_position or (@ladder_position == 0 and i == 1)}
                    class="absolute right-0 top-0 -translate-y-1/2 rounded-full bg-brand px-3 py-1 text-xs font-bold text-stone-950 shadow"
                  >
                    ← {if(@ladder_position == 0,
                      do: gettext("Start here"),
                      else: gettext("You are here")
                    )}
                  </span>
                  <strong class="block text-sm">{i}. {step.title}</strong>
                  <span class="block pr-2 text-sm text-white/70">{step.examples}</span>
                </div>
              </li>
            </ol>
          </section>
        </div>

        <div class="space-y-8">
          <div
            :if={@pending != []}
            id="pending-actions"
            class="rounded-3xl border-2 border-brand bg-brand-wash p-6 sm:p-8"
          >
            <h2 class="font-heading text-2xl uppercase tracking-wide text-stone-950">
              {gettext("Did you complete these actions?")}
            </h2>
            <p class="mt-2 leading-7 text-stone-700">
              {gettext(
                "We recorded these when you started them outside this journal. Please confirm whether you completed them."
              )}
            </p>

            <ul class="mt-5 space-y-3">
              <li
                :for={action <- @pending}
                id={"pending-#{action.id}"}
                class="flex flex-wrap items-center gap-3 rounded-2xl bg-white p-4"
              >
                <div class="mr-auto">
                  <p class="font-semibold text-stone-900">
                    {action_label(action.action_type, @locale)}
                  </p>
                  <p class="text-sm text-stone-500">{format_date(action.happened_on, @locale)}</p>
                </div>
                <button
                  type="button"
                  id={"confirm-#{action.id}"}
                  phx-click="confirm-action"
                  phx-value-id={action.id}
                  class="rounded-full bg-brand px-5 py-2.5 font-heading font-bold text-stone-950 transition hover:bg-brand-strong"
                >
                  {gettext("Yes, I did")}
                </button>
                <button
                  type="button"
                  id={"discard-#{action.id}"}
                  phx-click="discard-action"
                  phx-value-id={action.id}
                  class="rounded-full px-4 py-2.5 font-semibold text-stone-500 underline-offset-4 hover:text-stone-900 hover:underline"
                >
                  {gettext("No, remove it")}
                </button>
              </li>
            </ul>
          </div>

          <div id="action-editor" class="rounded-3xl bg-stone-900 p-6 text-white shadow-xl sm:p-8">
            <h2 class="font-serif text-3xl">
              {if(@editing_id, do: gettext("Edit action"), else: gettext("Record an action"))}
            </h2>
            <.form
              for={@form}
              id="action-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-6 space-y-5"
            >
              <.input
                field={@form[:action_type]}
                type="select"
                label={gettext("What did you do?")}
                prompt={gettext("Choose an action")}
                options={Enum.map(Action.action_types(), &{action_label(&1, @locale), &1})}
                class="w-full select bg-white text-stone-950"
              />
              <.input
                field={@form[:happened_on]}
                type="date"
                label={gettext("When?")}
                lang={gettext("en-CA")}
                class="w-full input bg-white text-stone-950"
              />
              <.input
                :if={Action.location?(@selected_type)}
                field={@form[:location]}
                type="text"
                label="Where?"
                placeholder="Montréal, Concordia University, Rue Sainte-Catherine…"
                class="w-full input bg-white text-stone-950 placeholder:text-stone-500"
              />
              <.input
                :if={Action.quantity?(@selected_type)}
                field={@form[:quantity]}
                type="number"
                label={quantity_label(@selected_type)}
                min="0"
                class="w-full input bg-white text-stone-950"
              />
              <.input
                field={@form[:notes]}
                type="textarea"
                label="Private note (optional)"
                placeholder="What did you learn? What might you try next?"
                class="w-full textarea bg-white text-stone-950 placeholder:text-stone-500"
              />
              <div class="flex gap-3">
                <button
                  id="save-action"
                  class="rounded-full bg-brand px-5 py-3 font-semibold text-white hover:bg-brand-strong"
                >
                  {if(@editing_id,
                    do: gettext("Save changes"),
                    else: gettext("Record privately")
                  )}
                </button>
                <button
                  :if={@editing_id}
                  type="button"
                  phx-click="cancel"
                  class="rounded-full border border-white/30 px-5 py-3 font-semibold"
                >
                  Cancel
                </button>
              </div>
            </.form>
          </div>

          <div id="actions" phx-update="stream" class="space-y-3">
            <div
              id="actions-empty"
              class="hidden rounded-3xl border border-dashed border-stone-300 p-8 text-center text-stone-500 only:block"
            >
              No actions yet. Record the first thing you have already done.
            </div>
            <article
              :for={{id, action} <- @streams.actions}
              id={id}
              class="rounded-3xl border border-stone-200 bg-white p-6 shadow-sm"
            >
              <div class="flex items-start justify-between gap-5">
                <div>
                  <p class="font-semibold text-stone-900">
                    {action_label(action.action_type, @locale)}
                  </p>
                  <time class="mt-1 block text-sm text-stone-500">{Calendar.strftime(
                    action.happened_on,
                    "%B %-d, %Y"
                  )}</time>
                  <p
                    :if={action.location not in [nil, ""] or action.quantity}
                    class="mt-1 text-sm text-brand-ink"
                  >
                    <span :if={action.location not in [nil, ""]}>{action.location}</span>
                    <span :if={action.location not in [nil, ""] and action.quantity}> · </span>
                    <span :if={action.quantity}>{action.quantity} {unit(action.action_type)}</span>
                  </p>
                  <p
                    :if={action.notes not in [nil, ""]}
                    class="mt-3 whitespace-pre-line text-stone-600"
                  >
                    {action.notes}
                  </p>
                </div>
                <div class="flex gap-2">
                  <button
                    phx-click="edit"
                    phx-value-id={action.id}
                    class="text-sm font-medium text-stone-600 hover:text-stone-950"
                  >Edit</button>
                  <button
                    phx-click="delete"
                    phx-value-id={action.id}
                    data-confirm="Delete this private action?"
                    class="text-sm font-medium text-red-700 hover:text-red-900"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </article>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
