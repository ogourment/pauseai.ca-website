defmodule PauseAiCaWeb.CampaignPrompt do
  @moduledoc """
  The action call of the day, offered without interrupting the reading.

  The home page's job is the curiosity-to-action journey. This prompt carries
  whatever is urgent right now and appears a few seconds in, after the visitor
  has had a chance to start reading. It is dismissible, remembers the dismissal
  in `localStorage`, closes on Escape or backdrop click, and traps nothing that
  a keyboard user cannot get out of.

  It never appears for someone who has already dismissed this campaign, and it
  never appears before the page is readable, so a visitor who came to read is
  not blocked from reading.
  """

  # Phoenix.Component rather than `use PauseAiCaWeb, :html`: this module is
  # imported into html_helpers, so using it here would be circular.
  use Phoenix.Component

  attr :locale, :string, required: true
  attr :href, :string, required: true
  attr :campaign_id, :string, required: true
  attr :delay, :integer, default: 7_000

  def campaign_prompt(assigns) do
    ~H"""
    <div
      id="campaign-prompt"
      phx-hook=".CampaignPrompt"
      phx-update="ignore"
      data-campaign={@campaign_id}
      data-delay={@delay}
      hidden
    >
      <div
        id="campaign-prompt-backdrop"
        class="fixed inset-0 z-50 flex items-end justify-center bg-stone-950/40 p-4 sm:items-center"
      >
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="campaign-prompt-title"
          class="w-full max-w-lg overflow-hidden rounded-2xl bg-white shadow-2xl"
        >
          <p class="bg-brand px-5 py-2.5 text-center font-heading text-xs font-bold uppercase tracking-[0.16em] text-stone-950">
            {badge(@locale)}
          </p>

          <div class="p-7">
            <h2 id="campaign-prompt-title" class="font-heading text-3xl leading-tight text-stone-950">
              {title(@locale)}
            </h2>
            <p class="mt-3 leading-7 text-stone-600">{body(@locale)}</p>

            <div class="mt-6 flex flex-wrap gap-3">
              <.link
                id="campaign-prompt-accept"
                navigate={@href}
                class="rounded-full bg-brand px-6 py-3 font-heading text-lg font-bold text-stone-950 transition hover:bg-brand-strong"
              >
                {accept(@locale)}
              </.link>
              <button
                type="button"
                id="campaign-prompt-dismiss"
                class="rounded-full px-5 py-3 font-semibold text-stone-500 underline-offset-4 hover:text-stone-900 hover:underline"
              >
                {dismiss(@locale)}
              </button>
            </div>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CampaignPrompt">
        export default {
          mounted() {
            const key = `pauseai-ca:campaign-dismissed:${this.el.dataset.campaign}`
            let dismissed = false
            try { dismissed = localStorage.getItem(key) === "true" } catch (_e) {}
            if (dismissed) return

            const reveal = () => {
              this.el.hidden = false
              document.body.style.overflow = "hidden"
              this.el.querySelector("#campaign-prompt-accept")?.focus()
            }

            const close = () => {
              this.el.hidden = true
              document.body.style.overflow = ""
              try { localStorage.setItem(key, "true") } catch (_e) {}
              document.removeEventListener("keydown", onKeydown)
            }

            const onKeydown = (event) => { if (event.key === "Escape") close() }

            this.timer = setTimeout(() => {
              reveal()
              document.addEventListener("keydown", onKeydown)
            }, Number(this.el.dataset.delay) || 7000)

            this.el.querySelector("#campaign-prompt-dismiss")?.addEventListener("click", close)
            this.el.querySelector("#campaign-prompt-accept")?.addEventListener("click", close)
            this.el.querySelector("#campaign-prompt-backdrop")?.addEventListener("click", (event) => {
              if (event.target.id === "campaign-prompt-backdrop") close()
            })
          },

          destroyed() {
            clearTimeout(this.timer)
            document.body.style.overflow = ""
          }
        }
      </script>
    </div>
    """
  end

  defp badge("fr"), do: "Protocole Tir de semonce · Deuxième activation"
  defp badge(_locale), do: "Warning Shot Protocol · Second activation"

  defp title("fr"),
    do: "Une IA s'est échappée de son laboratoire et a piraté une vraie entreprise"

  defp title(_locale), do: "An AI escaped its lab and hacked a real company"

  defp body("fr"),
    do:
      "Ce n'est plus hypothétique: cela a une date, une victime et un rapport d'incident. Voici ce qui s'est passé, et les deux gestes qui comptent aujourd'hui."

  defp body(_locale),
    do:
      "This is no longer hypothetical: it has a date, a victim and an incident report. Here is what happened, and the two things that matter today."

  defp accept("fr"), do: "Voir ce qui s'est passé"
  defp accept(_locale), do: "See what happened"

  defp dismiss("fr"), do: "Plus tard"
  defp dismiss(_locale), do: "Not now"
end
