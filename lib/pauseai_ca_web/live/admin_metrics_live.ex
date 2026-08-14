defmodule PauseAiCaWeb.AdminMetricsLive do
  use PauseAiCaWeb, :live_view

  alias PauseAiCa.Engagement
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
  def handle_params(_params, _uri, %{assigns: %{live_action: :redirect}} = socket) do
    {:noreply, push_navigate(socket, to: ~p"/admin/dashboard")}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  defp load(socket) do
    metrics = Engagement.metrics()

    socket
    |> assign(:page_title, gettext("Admin dashboard"))
    |> assign(:metrics, metrics)
    |> assign(:trend_period_label, trend_period_label(metrics.trend_period))
    |> assign(
      :ladder_counts,
      List.replace_at(Ladder.counts(metrics.by_type), 0, metrics.learning_people)
    )
    |> assign(
      :ladder_trends,
      List.replace_at(
        Ladder.trends(metrics.trends.action_types),
        0,
        List.duplicate(0, length(metrics.trends.visits))
      )
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="admin-dashboard" class="mx-auto max-w-6xl px-5 py-16">
        <p class="eyebrow">{gettext("Superadmin")}</p>
        <h1 class="mt-3 font-heading text-5xl text-stone-950">{gettext("Admin dashboard")}</h1>
        <.admin_navigation current={:dashboard} />
        <section id="admin-metrics" class="mt-10">
          <h2 class="font-heading text-3xl text-stone-950">Movement metrics</h2>
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
                    <.learning_breakdown
                      :if={i == 1}
                      count={count}
                      breakdown={@metrics.learning_breakdown}
                    />
                    <span
                      :if={i != 1}
                      class="rounded-full bg-brand px-3 py-1 text-sm font-bold text-stone-950"
                    >
                      {count} {if(count == 1, do: "action", else: "actions")}
                    </span>
                  </div>
                </div>
              </li>
            </ol>
          </section>
        </section>
      </section>
    </Layouts.app>
    """
  end

  attr :count, :integer, required: true
  attr :breakdown, :map, required: true

  defp learning_breakdown(assigns) do
    ~H"""
    <details id="learning-breakdown" class="group relative">
      <summary class="cursor-pointer list-none rounded-full bg-brand px-3 py-1 text-sm font-bold text-stone-950 outline-none ring-brand focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-offset-stone-900">
        {@count} {if(@count == 1, do: "person", else: "people")}
        <span aria-hidden="true" class="ml-1">ⓘ</span>
      </summary>
      <div class="absolute right-0 z-20 mt-2 w-72 rounded-2xl border border-stone-200 bg-white p-4 text-stone-900 shadow-2xl">
        <p class="font-bold">Distinct learning signals</p>
        <p class="mt-1 text-xs leading-5 text-stone-500">
          A person may appear in several rows but counts once in the total.
        </p>
        <dl class="mt-3 space-y-2 text-sm">
          <.breakdown_row
            id="questions-answered"
            label="Answered a homepage question"
            value={@breakdown.question_answers}
          />
          <.breakdown_row
            id="questionnaire-completed"
            label="Completed all homepage questions"
            value={@breakdown.questionnaires_completed}
          />
          <.breakdown_row
            id="learn-visited"
            label="Visited Learn"
            value={@breakdown.learn_page_visitors}
          />
          <.breakdown_row
            id="resource-opened"
            label="Opened a resource"
            value={@breakdown.resources_opened}
          />
          <.breakdown_row
            id="resource-bookmarked"
            label="Bookmarked a resource"
            value={@breakdown.resources_bookmarked}
          />
          <.breakdown_row
            id="learning-self-reported"
            label="Self-reported learning"
            value={@breakdown.self_reported}
          />
        </dl>
      </div>
    </details>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp breakdown_row(assigns) do
    ~H"""
    <div id={@id} class="flex items-baseline justify-between gap-4">
      <dt>{@label}</dt>
      <dd class="font-bold">{@value}</dd>
    </div>
    """
  end

  attr :current, :atom, required: true

  defp admin_navigation(assigns) do
    ~H"""
    <nav class="mt-8 flex flex-wrap gap-3" aria-label={gettext("Superadmin tools")}>
      <.link
        navigate={~p"/admin/dashboard"}
        aria-current={if @current == :dashboard, do: "page"}
        class={admin_link_class(@current == :dashboard)}
      >{gettext("Dashboard")}</.link>
      <.link
        navigate={~p"/admin/accounts"}
        aria-current={if @current == :accounts, do: "page"}
        class={admin_link_class(@current == :accounts)}
      >{gettext("Accounts")}</.link>
      <a href="/admin/versions" class={admin_link_class(false)}>{gettext("Deployment versions")}</a>
      <a href="/admin/acceptance" class={admin_link_class(false)}>{gettext("Acceptance evidence")}</a>
    </nav>
    """
  end

  defp admin_link_class(current?) do
    [
      "rounded-full border px-4 py-2 text-sm font-semibold transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand",
      if(current?,
        do: "border-stone-900 bg-stone-900 text-white",
        else: "border-stone-300 bg-white text-stone-800 hover:border-brand"
      )
    ]
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
