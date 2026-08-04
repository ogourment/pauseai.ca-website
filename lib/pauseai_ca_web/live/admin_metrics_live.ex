defmodule PauseAiCaWeb.AdminMetricsLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.{Accounts, Engagement}
  alias PauseAiCa.Engagement.Ladder

  @impl true
  def mount(_params, _session, socket) do
    if socket.assigns.current_scope.user.superadmin do
      {:ok, load(socket)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Superadmin access required.")
       |> push_navigate(to: ~p"/dashboard")}
    end
  end

  @impl true
  def handle_event("set-superadmin", %{"id" => id, "value" => value}, socket) do
    target = Accounts.get_user!(id)

    case Accounts.set_superadmin(socket.assigns.current_scope.user, target, value == "true") do
      {:ok, _user} ->
        {:noreply, load(socket)}

      {:error, :last_superadmin} ->
        {:noreply, put_flash(socket, :error, "The last superadmin cannot be removed.")}

      {:error, :email_unconfirmed} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Confirm this account's email before granting superadmin access."
         )}
    end
  end

  defp load(socket) do
    metrics = Engagement.metrics()

    socket
    |> assign(:page_title, "Movement metrics")
    |> assign(:metrics, metrics)
    |> assign(:ladder_counts, Ladder.counts(metrics.by_type))
    |> assign(:users, Accounts.list_users())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="admin-metrics" class="mx-auto max-w-6xl px-5 py-16">
        <p class="eyebrow">Superadmin</p>
        <h1 class="mt-3 font-heading text-5xl text-stone-950">Movement metrics</h1>
        <p class="mt-4 max-w-3xl text-stone-600">
          First-party database totals from accounts and confirmed private action records. Analytics may complement these figures, but is not their source.
        </p>
        <div class="mt-9 grid gap-4 sm:grid-cols-3">
          <.metric id="metric-users" label="Accounts" value={@metrics.users} />
          <.metric
            id="metric-active"
            label="People with a confirmed action"
            value={@metrics.active_people}
          />
          <.metric id="metric-actions" label="Confirmed actions" value={@metrics.actions} />
        </div>
        <section class="mt-10 rounded-[2rem] bg-stone-900 p-8 text-white sm:p-10">
          <h2 class="font-heading text-3xl">Progress through the engagement ladder</h2>
          <ol id="metrics-by-type" class="mx-auto mt-8 flex max-w-2xl flex-col-reverse px-2 sm:px-8">
            <li
              :for={
                {{step, count}, i} <-
                  Enum.zip(Ladder.steps("en"), @ladder_counts) |> Enum.with_index(1)
              }
              class="border-x-[8px] border-white/30 px-5 pb-6"
            >
              <div class="flex items-start gap-4 border-t-[8px] border-white/30 pt-3">
                <div class="mr-auto">
                  <strong class="block">{i}. {step.title}</strong>
                  <span class="mt-1 block text-sm text-white/70">{step.examples}</span>
                </div>
                <span class="rounded-full bg-brand px-3 py-1 text-sm font-bold text-stone-950">
                  {count} {if(count == 1, do: "action", else: "actions")}
                </span>
              </div>
            </li>
          </ol>
        </section>
        <nav class="mt-10 flex flex-wrap gap-3" aria-label="Superadmin tools">
          <a
            href="/admin/versions"
            class="rounded-full border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-800 hover:border-brand"
          >Deployment versions</a>
          <a
            href="/admin/acceptance"
            class="rounded-full border border-stone-300 bg-white px-4 py-2 text-sm font-semibold text-stone-800 hover:border-brand"
          >Acceptance evidence</a>
        </nav>
        <section class="mt-10 rounded-3xl border border-stone-200 bg-white p-7">
          <h2 class="font-heading text-3xl text-stone-950">Superadmins</h2>
          <ul id="admin-users" class="mt-5 divide-y divide-stone-100">
            <li
              :for={user <- @users}
              id={"admin-user-#{user.id}"}
              class="flex flex-wrap items-center gap-4 py-3"
            >
              <span class="mr-auto">{user.email}</span>
              <span :if={user.superadmin} class="text-sm font-semibold text-brand-ink">Superadmin</span>
              <span :if={is_nil(user.confirmed_at)} class="text-sm text-stone-500">Email unconfirmed</span>
              <button
                id={"admin-toggle-#{user.id}"}
                phx-click="set-superadmin"
                phx-value-id={user.id}
                phx-value-value={to_string(!user.superadmin)}
                disabled={!user.superadmin and is_nil(user.confirmed_at)}
                class="rounded-full border border-stone-300 px-4 py-2 text-sm font-semibold text-stone-800 hover:border-brand disabled:cursor-not-allowed disabled:opacity-40"
              >
                {if(user.superadmin, do: "Remove role", else: "Make superadmin")}
              </button>
            </li>
          </ul>
        </section>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp metric(assigns) do
    ~H"""
    <div id={@id} class="rounded-3xl bg-stone-900 p-6 text-white">
      <p class="text-sm text-white/70">{@label}</p>
      <p class="mt-2 font-heading text-5xl">{@value}</p>
    </div>
    """
  end
end
