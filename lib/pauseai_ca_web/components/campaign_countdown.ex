defmodule PauseAiCaWeb.CampaignCountdown do
  @moduledoc "One accessible, server-clock countdown shared by the campaign banner and donation page."
  use PauseAiCaWeb, :html

  def deadline(state), do: gettext("Campaign closes %{date}.", date: state.closing_date)

  attr :state, :map, required: true
  attr :id, :string, required: true
  attr :compact, :boolean, default: false

  def timer(assigns) do
    assigns =
      assign(
        assigns,
        :menu_units,
        if(assigns.state.seconds >= 86_400, do: [:days, :hours], else: [:hours, :minutes])
      )

    ~H"""
    <span
      id={@id}
      phx-hook=".Countdown"
      role="timer"
      aria-live="off"
      aria-label={
        Enum.map_join(
          if(@compact, do: @menu_units, else: [:days, :hours, :minutes, :seconds]),
          " ",
          fn unit -> "#{Map.fetch!(@state.parts, unit)} #{unit_label(unit)}" end
        )
      }
      data-label-days={gettext("days")}
      data-label-hours={gettext("hours")}
      data-label-minutes={gettext("minutes")}
      data-label-seconds={gettext("seconds")}
      data-label-ended={gettext("This campaign has ended.")}
      data-now={DateTime.to_iso8601(@state.now)}
      data-closes-at={DateTime.to_iso8601(@state.closes_at)}
      data-urgent-at={DateTime.to_iso8601(@state.urgent_at)}
      data-compact={to_string(@compact)}
      hidden={@compact && !@state.urgent?}
      class={if @compact, do: "inline-flex items-center gap-1 text-[10px] leading-3", else: "block"}
    >
      <span data-countdown-active class={if @compact, do: "contents", else: "block"}>
        <span :if={!@compact} class="mb-2 block text-xs font-semibold uppercase tracking-wide">
          {gettext("Time left to support the campaign")}
        </span>
        <span
          data-countdown-digits
          hidden={@compact && !@state.urgent?}
          aria-hidden="true"
          class={if @compact, do: "inline-flex gap-1 tabular-nums", else: "flex gap-1.5"}
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
            data-countdown-part={unit}
            hidden={@compact && unit not in @menu_units}
            class={
              if @compact,
                do: "inline-flex items-baseline gap-0.5",
                else:
                  "flex min-w-0 flex-1 flex-col rounded-md bg-stone-950 px-1.5 py-2 text-center text-white"
            }
          >
            <span
              data-countdown-unit={unit}
              class={
                if @compact,
                  do: "font-bold",
                  else: "font-heading text-2xl font-bold tabular-nums sm:text-3xl"
              }
            >
              {Map.fetch!(@state.parts, unit) |> Integer.to_string() |> String.pad_leading(2, "0")}
            </span>
            <span :if={@compact} aria-hidden="true">{short_unit(unit)}</span>
            <span class={if @compact, do: "sr-only", else: "mt-1 text-[10px]"}>{label}</span>
          </span>
        </span>
        <span class={if @compact, do: "sr-only", else: "mt-2 block text-xs"}>
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
              const compact = this.el.dataset.compact === 'true'
              if (compact) this.el.hidden = ended || now < Date.parse(this.el.dataset.urgentAt)
              const promotion = document.querySelector('[data-campaign-promotion]')
              if (promotion?.dataset.campaignClosesAt === this.el.dataset.closesAt) promotion.hidden = ended
              const selected = !compact ? ['days', 'hours', 'minutes', 'seconds'] : remaining >= 86400 ? ['days', 'hours'] : ['hours', 'minutes']
              this.el.querySelectorAll('[data-countdown-part]').forEach(node => { node.hidden = compact && !selected.includes(node.dataset.countdownPart) })
              const digits = this.el.querySelector('[data-countdown-digits]')
              digits.hidden = ended || (this.el.dataset.compact === 'true' && now < Date.parse(this.el.dataset.urgentAt))
              const parts = {days: Math.floor(remaining / 86400), hours: Math.floor(remaining / 3600) % 24, minutes: Math.floor(remaining / 60) % 60, seconds: remaining % 60}
              this.el.setAttribute('aria-label', ended ? this.el.dataset.labelEnded : selected.map(unit => `${parts[unit]} ${this.el.dataset['label' + unit[0].toUpperCase() + unit.slice(1)]}`).join(' '))
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

  defp unit_label(:days), do: gettext("days")
  defp unit_label(:hours), do: gettext("hours")
  defp unit_label(:minutes), do: gettext("minutes")
  defp unit_label(:seconds), do: gettext("seconds")

  defp short_unit(:days),
    do: if(Gettext.get_locale(PauseAiCaWeb.Gettext) == "fr", do: "j", else: "d")

  defp short_unit(:hours), do: "h"
  defp short_unit(:minutes), do: "m"
  defp short_unit(:seconds), do: "s"
end
