defmodule PauseAiCaWeb.CampaignCountdown do
  @moduledoc "One accessible, server-clock countdown shared by the campaign banner and donation page."
  use PauseAiCaWeb, :html

  def deadline(state), do: gettext("Campaign closes %{date}.", date: state.closing_date)

  attr :state, :map, required: true
  attr :id, :string, required: true
  attr :compact, :boolean, default: false

  def timer(assigns) do
    ~H"""
    <span
      id={@id}
      phx-hook=".Countdown"
      data-now={DateTime.to_iso8601(@state.now)}
      data-closes-at={DateTime.to_iso8601(@state.closes_at)}
      data-urgent-at={DateTime.to_iso8601(@state.urgent_at)}
      data-compact={to_string(@compact)}
      class={if @compact, do: "inline-flex items-center gap-1.5", else: "block"}
    >
      <span data-countdown-active class={if @compact, do: "contents", else: "block"}>
        <span :if={!@compact} class="mb-3 block text-sm font-semibold uppercase tracking-wide">
          {gettext("Time left to support the campaign")}
        </span>
        <span
          data-countdown-digits
          hidden={@compact && !@state.urgent?}
          aria-hidden="true"
          class={
            if @compact, do: "inline-flex gap-1.5 tabular-nums", else: "flex max-w-md gap-2 sm:gap-3"
          }
        >
          <span
            :for={
              {unit, label} <- [
                {:days, gettext("days")},
                {:hours, gettext("hours")},
                {:minutes, gettext("minutes")},
                {:seconds, gettext("seconds")}
              ]
            }
            class={
              if @compact,
                do: "inline-flex items-baseline gap-1",
                else:
                  "flex min-w-0 flex-1 flex-col rounded-lg bg-stone-950 px-2 py-3 text-center text-white"
            }
          >
            <span
              data-countdown-unit={unit}
              class={
                if @compact,
                  do: "font-bold",
                  else: "font-heading text-4xl font-bold tabular-nums sm:text-5xl"
              }
            >
              {Map.fetch!(@state.parts, unit) |> Integer.to_string() |> String.pad_leading(2, "0")}
            </span>
            <span class={if @compact, do: "text-xs", else: "mt-1 text-xs sm:text-sm"}>{label}</span>
          </span>
        </span>
        <span class={if @compact, do: "sr-only", else: "mt-3 block text-sm"}>
          {deadline(@state)}
        </span>
      </span>
      <span data-countdown-ended hidden class="font-semibold">{gettext("This campaign has ended.")}</span>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Countdown">
        export default {
          mounted() {
            this.syncClock = () => {
              this.serverNow = Date.parse(this.el.dataset.now)
              this.started = performance.now()
            }
            this.tick = () => {
              const now = this.serverNow + performance.now() - this.started
              const end = Date.parse(this.el.dataset.closesAt)
              const remaining = Math.max(0, Math.floor((end - now) / 1000))
              const ended = now >= end
              this.el.querySelector('[data-countdown-active]').hidden = ended
              this.el.querySelector('[data-countdown-ended]').hidden = !ended
              const promotion = this.el.closest('[data-campaign-promotion]')
              if (promotion) promotion.hidden = ended
              const digits = this.el.querySelector('[data-countdown-digits]')
              digits.hidden = ended || (this.el.dataset.compact === 'true' && now < Date.parse(this.el.dataset.urgentAt))
              const parts = {days: Math.floor(remaining / 86400), hours: Math.floor(remaining / 3600) % 24, minutes: Math.floor(remaining / 60) % 60, seconds: remaining % 60}
              for (const [unit, value] of Object.entries(parts)) {
                const node = this.el.querySelector(`[data-countdown-unit="${unit}"]`)
                const text = String(value).padStart(2, '0')
                if (node.textContent.trim() !== text) node.textContent = text
              }
              if (ended && this.interval) { clearInterval(this.interval); this.interval = null }
            }
            this.syncClock()
            this.tick()
            if (Date.parse(this.el.dataset.closesAt) > this.serverNow) this.interval = setInterval(this.tick, 1000)
          },
          updated() {
            this.syncClock()
            this.tick()
            if (!this.interval && Date.parse(this.el.dataset.closesAt) > this.serverNow) this.interval = setInterval(this.tick, 1000)
          },
          destroyed() { clearInterval(this.interval) }
        }
      </script>
    </span>
    """
  end
end
