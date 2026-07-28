defmodule PauseAiCaWeb.DashboardLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Engagement
  alias PauseAiCa.Engagement.Action

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    actions = Engagement.list_actions(scope)

    {:ok,
     socket
     |> assign(:page_title, "My actions")
     |> assign(:action_count, length(actions))
     |> assign(:editing_id, nil)
     |> assign_form(Engagement.new_action(scope))
     |> stream(:actions, actions)}
  end

  @impl true
  def handle_event("validate", %{"action" => params}, socket) do
    changeset =
      socket.assigns.current_scope
      |> Engagement.change_action(form_action(socket), params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"action" => params}, socket) do
    if socket.assigns.editing_id do
      update_action(socket, params)
    else
      create_action(socket, params)
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    action = Engagement.get_action!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(:editing_id, action.id)
     |> assign_form(action)}
  end

  def handle_event("cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_id, nil)
     |> assign_form(Engagement.new_action(socket.assigns.current_scope))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    action = Engagement.get_action!(socket.assigns.current_scope, id)
    {:ok, _action} = Engagement.delete_action(socket.assigns.current_scope, action)

    {:noreply,
     socket
     |> update(:action_count, &max(&1 - 1, 0))
     |> stream_delete(:actions, action)}
  end

  defp create_action(socket, params) do
    case Engagement.create_action(socket.assigns.current_scope, params) do
      {:ok, action} ->
        {:noreply,
         socket
         |> put_flash(:info, "Action recorded privately.")
         |> update(:action_count, &(&1 + 1))
         |> stream_insert(:actions, action, at: 0)
         |> assign_form(Engagement.new_action(socket.assigns.current_scope))}

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
         |> stream_insert(:actions, action)
         |> assign_form(Engagement.new_action(socket.assigns.current_scope))}

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

  defp action_label("learned"), do: "Read or watched a resource"
  defp action_label("conversation"), do: "Discussed AI risk with someone"
  defp action_label("event"), do: "Attended an event"
  defp action_label("contacted_representative"), do: "Contacted a representative"
  defp action_label("met_representative"), do: "Met a representative"
  defp action_label("volunteered"), do: "Volunteered"
  defp action_label("organized"), do: "Organized an activity"
  defp action_label("other"), do: "Other private action"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="mx-auto grid max-w-6xl gap-10 px-5 py-12 lg:grid-cols-[0.8fr_1.2fr] lg:py-20">
        <div>
          <p class="eyebrow">Your private workspace</p>
          <h1 class="mt-3 font-serif text-5xl leading-tight text-stone-950">
            Small actions become capacity.
          </h1>
          <p class="mt-5 max-w-lg text-lg leading-8 text-stone-600">
            Keep a private record of what you have tried. This prototype does not publish,
            rank, or include your actions in public movement statistics.
          </p>

          <div class="mt-8 rounded-3xl border border-stone-200 bg-white p-6 shadow-sm">
            <p class="text-sm font-semibold uppercase tracking-widest text-[#b94628]">
              {@action_count} actions recorded
            </p>
            <p class="mt-3 text-stone-600">
              Suggested next step: choose one person you trust and share one resource that
              helped you understand the issue.
            </p>
          </div>
        </div>

        <div class="space-y-8">
          <div class="rounded-3xl bg-stone-900 p-6 text-white shadow-xl sm:p-8">
            <h2 class="font-serif text-3xl">
              {if(@editing_id, do: "Edit action", else: "Record an action")}
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
                label="What did you do?"
                prompt="Choose an action"
                options={Enum.map(Action.action_types(), &{action_label(&1), &1})}
              />
              <.input field={@form[:happened_on]} type="date" label="When?" />
              <.input
                field={@form[:notes]}
                type="textarea"
                label="Private note (optional)"
                placeholder="What did you learn? What might you try next?"
              />
              <div class="flex gap-3">
                <button
                  id="save-action"
                  class="rounded-full bg-[#ef5b35] px-5 py-3 font-semibold text-white hover:bg-[#d84b29]"
                >
                  {if(@editing_id, do: "Save changes", else: "Record privately")}
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
                  <p class="font-semibold text-stone-900">{action_label(action.action_type)}</p>
                  <time class="mt-1 block text-sm text-stone-500">{Calendar.strftime(
                    action.happened_on,
                    "%B %-d, %Y"
                  )}</time>
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
