defmodule PauseAiCaWeb.AdminMetricsLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.{Accounts, Engagement}
  alias PauseAiCa.Accounts.UserNotifier
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

    promote? = value == "true"

    case Accounts.set_superadmin(socket.assigns.current_scope.user, target, promote?) do
      {:ok, user} ->
        message = if promote?, do: "Superadmin role granted.", else: "Superadmin role removed."

        {:noreply,
         socket
         |> load()
         |> put_flash(:info, message)
         |> notify_new_superadmin(user, promote?)}

      {:error, :last_superadmin} ->
        {:noreply, put_flash(socket, :error, "The last superadmin cannot be removed.")}

      {:error, :email_unconfirmed} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Confirm this account's email before granting superadmin access."
         )}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Superadmin access required.")}
    end
  end

  defp notify_new_superadmin(socket, _user, false), do: socket

  defp notify_new_superadmin(socket, user, true) do
    url = PauseAiCaWeb.Endpoint.url() <> "/admin/metrics"

    case UserNotifier.deliver_superadmin_granted(user, url) do
      {:ok, _email} ->
        socket

      {:error, _reason} ->
        put_flash(socket, :error, "Role granted, but the notification email could not be sent.")
    end
  end

  defp load(socket) do
    metrics = Engagement.metrics()

    socket
    |> assign(:page_title, "Movement metrics")
    |> assign(:metrics, metrics)
    |> assign(:trend_period_label, trend_period_label(metrics.trend_period))
    |> assign(:ladder_counts, Ladder.counts(metrics.by_type))
    |> assign(:ladder_trends, Ladder.trends(metrics.trends.action_types))
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
          First-party database totals from accounts, anonymous daily visits, and confirmed private action records. Analytics may complement these figures, but is not their source.
        </p>
        <p id="metrics-period" class="mt-8 text-xs font-medium text-stone-500">
          Daily trends · {@trend_period_label} (UTC)
        </p>
        <div class="mt-2 grid gap-4 sm:grid-cols-4">
          <.metric
            id="metric-users"
            label="Accounts"
            value={@metrics.users}
            trend={@metrics.trends.users}
            trend_period={@trend_period_label}
          />
          <.metric
            id="metric-active"
            label="People with a confirmed action"
            value={@metrics.active_people}
            trend={@metrics.trends.active_people}
            trend_period={@trend_period_label}
          />
          <.metric
            id="metric-actions"
            label="Confirmed actions"
            value={@metrics.actions}
            trend={@metrics.trends.actions}
            trend_period={@trend_period_label}
          />
          <.metric
            id="metric-visits"
            label="Visits"
            value={@metrics.visits}
            trend={@metrics.trends.visits}
            trend_period={@trend_period_label}
          />
        </div>
        <section class="mt-10 rounded-[2rem] bg-stone-900 p-8 text-white sm:p-10">
          <h2 class="font-heading text-3xl">Progress through the engagement ladder</h2>
          <p class="mt-2 text-xs font-medium text-white/60">
            Daily trends · {@trend_period_label} (UTC)
          </p>
          <ol id="metrics-by-type" class="mx-auto mt-8 flex max-w-2xl flex-col-reverse px-2 sm:px-8">
            <li
              :for={
                {{step, count, trend}, i} <-
                  Enum.zip([Ladder.steps("en"), @ladder_counts, @ladder_trends])
                  |> Enum.with_index(1)
              }
              class="border-x-[8px] border-white/30 px-5 pb-6"
            >
              <div class="flex items-start gap-4 border-t-[8px] border-white/30 pt-3">
                <div class="mr-auto">
                  <strong class="block">{i}. {step.title}</strong>
                  <span class="mt-1 block text-sm text-white/70">{step.examples}</span>
                </div>
                <div class="flex shrink-0 items-end gap-3">
                  <.ladder_sparkline
                    label={step.title}
                    trend={trend}
                    trend_period={@trend_period_label}
                  />
                  <span class="rounded-full bg-brand px-3 py-1 text-sm font-bold text-stone-950">
                    {count} {if(count == 1, do: "action", else: "actions")}
                  </span>
                </div>
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
  attr :trend, :list, required: true
  attr :trend_period, :string, required: true

  defp metric(assigns) do
    assigns =
      assigns
      |> assign(:points, sparkline_points(assigns.trend))
      |> assign(:daily_max, Enum.max(assigns.trend, fn -> 0 end))

    ~H"""
    <div id={@id} class="rounded-3xl bg-stone-900 p-6 text-white">
      <p class="text-sm text-white/70">{@label}</p>
      <div class="mt-2 flex items-end justify-between gap-4">
        <p class="font-heading text-5xl">{@value}</p>
        <div :if={@daily_max > 0} class="flex shrink-0 flex-col items-end text-brand">
          <span data-role="daily-max" class="h-4 text-xs font-bold">
            {if @daily_max > 0, do: @daily_max}
          </span>
          <svg
            class="h-10 w-24"
            viewBox="0 0 96 48"
            role="img"
            aria-label={"#{@label}, daily trend, #{@trend_period}; daily maximum #{@daily_max}"}
          >
            <title>
              {@label}, daily trend, {@trend_period}; daily maximum {@daily_max}
            </title>
            <polyline
              points={@points}
              fill="none"
              stroke="currentColor"
              stroke-width="3"
              stroke-linecap="round"
              stroke-linejoin="round"
              vector-effect="non-scaling-stroke"
            />
          </svg>
        </div>
      </div>
    </div>
    """
  end

  defp sparkline_points(values) do
    max_value = max(Enum.max(values, fn -> 0 end), 1)
    intervals = max(length(values) - 1, 1)

    values
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {value, index} ->
      x = Float.round(index * 96 / intervals, 1)
      y = Float.round(44 - value * 40 / max_value, 1)
      "#{x},#{y}"
    end)
  end

  attr :label, :string, required: true
  attr :trend, :list, required: true
  attr :trend_period, :string, required: true

  defp ladder_sparkline(assigns) do
    assigns =
      assigns
      |> assign(:points, sparkline_points(assigns.trend))
      |> assign(:daily_max, Enum.max(assigns.trend, fn -> 0 end))

    ~H"""
    <div
      :if={@daily_max > 0}
      data-role="ladder-trend"
      data-label={@label}
      class="flex flex-col items-end text-brand"
    >
      <span data-role="daily-max" class="h-4 text-xs font-bold">
        {if @daily_max > 0, do: @daily_max}
      </span>
      <svg
        class="h-8 w-20"
        viewBox="0 0 96 48"
        role="img"
        aria-label={"#{@label}, daily confirmed actions, #{@trend_period}; daily maximum #{@daily_max}"}
      >
        <title>
          {@label}, daily confirmed actions, {@trend_period}; daily maximum {@daily_max}
        </title>
        <polyline
          points={@points}
          fill="none"
          stroke="currentColor"
          stroke-width="3"
          stroke-linecap="round"
          stroke-linejoin="round"
          vector-effect="non-scaling-stroke"
        />
      </svg>
    </div>
    """
  end

  defp trend_period_label(%{start: start_date, end: end_date}) do
    start_label = Calendar.strftime(start_date, "%B %-d")
    end_label = Calendar.strftime(end_date, "%B %-d, %Y")
    "#{start_label}–#{end_label}"
  end
end
