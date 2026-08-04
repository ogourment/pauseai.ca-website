defmodule PauseAiCaWeb.DashboardLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Accounts
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
     |> assign(:page_title, if(locale == "fr", do: "Mes actions", else: "My actions"))
     |> assign(
       :recommendation,
       Ladder.recommendation(confirmed_actions, locale)
     )
     |> assign(:ladder_position, Ladder.position(confirmed_actions))
     |> assign(:action_count, Enum.count(actions, &(not Action.pending?(&1))))
     |> assign(:pending, Engagement.list_pending_actions(scope))
     |> assign(:editing_id, nil)
     |> assign(:selected_type, nil)
     |> assign(:needs_local_context, is_nil(scope.user.fsa))
     |> assign(:saved_resources, scope.user.saved_resources)
     |> assign(
       :local_context_form,
       to_form(Accounts.change_user_local_context(scope.user), as: "local_context")
     )
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

  def handle_event("save-local-context", %{"local_context" => params}, socket) do
    case Accounts.update_user_local_context(socket.assigns.current_scope.user, params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> assign(:needs_local_context, false)
         |> put_flash(
           :info,
           if(socket.assigns.locale == "fr", do: "Région enregistrée.", else: "Region saved.")
         )}

      {:error, changeset} ->
        {:noreply, assign(socket, :local_context_form, to_form(changeset, as: "local_context"))}
    end
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

  defp saved_resource_label("risk", "fr"), do: "Comprendre le risque existentiel"
  defp saved_resource_label("risk", _), do: "Understand existential risk"
  defp saved_resource_label("pause", "fr"), do: "Comprendre une pause"
  defp saved_resource_label("pause", _), do: "Understand a pause"
  defp saved_resource_label("coordination", "fr"), do: "Tester la coordination"
  defp saved_resource_label("coordination", _), do: "Test coordination"
  defp saved_resource_label("agency", "fr"), do: "Passer à l’action"
  defp saved_resource_label("agency", _), do: "Move toward action"

  defp action_label(type, "fr") do
    %{
      "learned" => "Lu ou regardé une ressource",
      "conversation" => "Discuté des risques de l'IA",
      "event" => "Participé à un événement",
      "contacted_representative" => "Contacté une personne élue",
      "met_representative" => "Rencontré une personne élue",
      "joined" => "Rejoint PauseAI",
      "signed" => "Signé la déclaration",
      "flyered" => "Distribué des dépliants ou posé des affiches",
      "volunteered" => "Fait du bénévolat",
      "organized" => "Organisé une activité",
      "other" => "Autre action privée"
    }[type]
  end

  defp action_label("learned", _locale), do: "Read or watched a resource"
  defp action_label("conversation", _), do: "Discussed AI risk with someone"
  defp action_label("event", _), do: "Attended an event"
  defp action_label("contacted_representative", _), do: "Contacted a representative"
  defp action_label("met_representative", _), do: "Met a representative"
  defp action_label("joined", _), do: "Joined PauseAI"
  defp action_label("signed", _), do: "Signed the PauseAI statement"
  defp action_label("flyered", _), do: "Handed out flyers or put up posters"
  defp action_label("volunteered", _), do: "Volunteered"
  defp action_label("organized", _), do: "Organized an activity"
  defp action_label("other", _), do: "Other private action"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      locale={@locale}
      translated_path={if(@locale == "fr", do: ~p"/en/actions", else: ~p"/fr/actions")}
    >
      <section class="mx-auto grid max-w-6xl gap-10 px-5 py-12 lg:grid-cols-[0.8fr_1.2fr] lg:py-20">
        <div>
          <p class="eyebrow">
            {if(@locale == "fr", do: "Votre espace privé", else: "Your private workspace")}
          </p>
          <h1 class="mt-3 font-serif text-5xl leading-tight text-stone-950">
            {if(@locale == "fr",
              do: "Notez ce que vous avez fait et choisissez la suite.",
              else: "Record what you did and choose what comes next."
            )}
          </h1>

          <div
            :if={@needs_local_context}
            id="fsa-reminder"
            class="mt-8 rounded-3xl border border-brand/40 bg-brand-wash p-6"
          >
            <h2 class="font-serif text-2xl text-stone-950">
              {if(@locale == "fr", do: "Que pense votre député?", else: "Where does your MP stand?")}
            </h2>
            <p class="mt-2 leading-7 text-stone-600">
              {if(@locale == "fr",
                do:
                  "Votre RTA nous permet d’identifier votre circonscription et de vous envoyer des nouvelles locales plus pertinentes.",
                else: "Your FSA lets us identify your riding and send more relevant local updates."
              )}
            </p>
            <.form
              for={@local_context_form}
              id="local-context-form"
              phx-submit="save-local-context"
              class="mt-4 space-y-4"
            >
              <.input
                field={@local_context_form[:fsa]}
                type="text"
                label={
                  if(@locale == "fr",
                    do: "RTA (3 premiers caractères du code postal)",
                    else: "FSA (first 3 postal-code characters)"
                  )
                }
                placeholder={if(@locale == "fr", do: "H2X", else: "K1A")}
                maxlength="3"
                autocomplete="postal-code"
                class="w-full input bg-white text-stone-950 uppercase placeholder:text-stone-400"
              />
              <.input
                field={@local_context_form[:local_updates]}
                type="checkbox"
                label={
                  if(@locale == "fr",
                    do: "M’envoyer des nouvelles locales et les nouveaux développements importants",
                    else: "Send me local news and important new developments"
                  )
                }
              />
              <button class="rounded-full bg-stone-900 px-5 py-3 font-semibold text-white hover:bg-stone-700">
                {if(@locale == "fr", do: "Enregistrer ma région", else: "Save my region")}
              </button>
            </.form>
          </div>
          <p class="mt-5 max-w-lg text-lg leading-8 text-stone-600">
            {if(@locale == "fr",
              do:
                "Votre journal n'est visible que par vous. Seuls des totaux anonymisés servent à suivre la progression du mouvement.",
              else:
                "Your log is visible only to you. Only aggregate counts are used to understand movement progress."
            )}
          </p>

          <div
            :if={@saved_resources != []}
            id="saved-resources"
            class="mt-8 rounded-3xl border border-stone-200 bg-white p-6 shadow-sm"
          >
            <h2 class="font-serif text-2xl text-stone-950">
              {if(@locale == "fr", do: "À lire plus tard", else: "Saved for later")}
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
            </ul>
          </div>

          <div class="mt-8 rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <p class="text-sm font-semibold uppercase tracking-widest text-brand-ink">
              {@action_count} {if(@locale == "fr", do: "actions consignées", else: "actions recorded")}
            </p>
            <h2 id="suggested-next-step" class="mt-3 font-heading text-2xl text-stone-950">
              {@recommendation.title}
            </h2>
            <p class="mt-2 text-stone-600">{@recommendation.why}</p>
            <p class="mt-3 text-sm text-stone-500">
              {if(@locale == "fr", do: "Temps estimé", else: "Estimated time")}: {@recommendation.effort}
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
              {if(@locale == "fr", do: "D'autres façons d'agir", else: "Other ways to act")}
            </h2>
            <p class="mt-2 text-sm leading-6 text-white/70">
              {if(@locale == "fr",
                do:
                  "Votre prochaine étape suggérée n'est qu'une option. Choisissez ce qui vous convient maintenant.",
                else: "Your suggested next step is only one option. Choose what fits you now."
              )}
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
                      do: if(@locale == "fr", do: "Commencez ici", else: "Start here"),
                      else: if(@locale == "fr", do: "Vous êtes ici", else: "You are here")
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
              {if(@locale == "fr",
                do: "Avez-vous réalisé ces actions ?",
                else: "Did you complete these actions?"
              )}
            </h2>
            <p class="mt-2 leading-7 text-stone-700">
              {if(@locale == "fr",
                do:
                  "Nous les avons notées lorsque vous les avez commencées hors de ce journal. Confirmez-nous si vous les avez terminées.",
                else:
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
                  {if(@locale == "fr", do: "Oui, c'est fait", else: "Yes, I did")}
                </button>
                <button
                  type="button"
                  id={"discard-#{action.id}"}
                  phx-click="discard-action"
                  phx-value-id={action.id}
                  class="rounded-full px-4 py-2.5 font-semibold text-stone-500 underline-offset-4 hover:text-stone-900 hover:underline"
                >
                  {if(@locale == "fr", do: "Non, supprimer", else: "No, remove it")}
                </button>
              </li>
            </ul>
          </div>

          <div id="action-editor" class="rounded-3xl bg-stone-900 p-6 text-white shadow-xl sm:p-8">
            <h2 class="font-serif text-3xl">
              {if(@locale == "fr",
                do: if(@editing_id, do: "Modifier l'action", else: "Noter une action"),
                else: if(@editing_id, do: "Edit action", else: "Record an action")
              )}
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
                label={if(@locale == "fr", do: "Qu'avez-vous fait?", else: "What did you do?")}
                prompt={if(@locale == "fr", do: "Choisir une action", else: "Choose an action")}
                options={Enum.map(Action.action_types(), &{action_label(&1, @locale), &1})}
                class="w-full select bg-white text-stone-950"
              />
              <.input
                field={@form[:happened_on]}
                type="date"
                label={if(@locale == "fr", do: "Quand?", else: "When?")}
                lang={if(@locale == "fr", do: "fr-CA", else: "en-CA")}
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
                  {if(@locale == "fr",
                    do: if(@editing_id, do: "Enregistrer", else: "Noter en privé"),
                    else: if(@editing_id, do: "Save changes", else: "Record privately")
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
