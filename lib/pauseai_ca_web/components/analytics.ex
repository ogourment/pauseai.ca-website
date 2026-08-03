defmodule PauseAiCaWeb.Analytics do
  @moduledoc """
  Google Analytics, loaded only after the visitor agrees to it.

  Quebec's Law 25 requires consent before technology that profiles a person is
  switched on, and it requires the refusal to be as easy as the acceptance.
  Since PauseAI Canada is a Quebec organisation asking people to put their name
  to a political letter, shipping a tracker that starts before the banner is
  answered would be both unlawful and a poor look.

  So the gtag snippet is not in the page until someone accepts. Declining
  stores the refusal and loads nothing. The choice is kept in `localStorage`,
  not a cookie, so a refusal does not itself create the thing being refused.

  Set `GA_MEASUREMENT_ID` to switch it on; unset, the banner never appears.
  """

  use Phoenix.Component

  attr :measurement_id, :string, default: nil
  attr :locale, :string, default: "en"

  def analytics(assigns) do
    ~H"""
    <div
      :if={@measurement_id}
      id="analytics"
      phx-hook=".Analytics"
      phx-update="ignore"
      data-ga={@measurement_id}
    >
      <div
        id="consent-banner"
        hidden
        class="fixed inset-x-0 bottom-0 z-50 border-t-2 border-brand bg-white p-4 shadow-2xl"
      >
        <div class="mx-auto flex max-w-4xl flex-wrap items-center gap-4">
          <p class="mr-auto max-w-2xl text-sm leading-6 text-stone-700">
            {consent_text(@locale)}
          </p>
          <button
            type="button"
            id="consent-decline"
            class="rounded-full border-2 border-stone-300 px-5 py-2.5 font-semibold text-stone-800 hover:border-stone-500"
          >
            {decline_label(@locale)}
          </button>
          <button
            type="button"
            id="consent-accept"
            class="rounded-full bg-brand px-5 py-2.5 font-heading font-bold text-stone-950 hover:bg-brand-strong"
          >
            {accept_label(@locale)}
          </button>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Analytics">
        export default {
          mounted() {
            const key = "pauseai-ca:analytics-consent"
            const id = this.el.dataset.ga
            const banner = this.el.querySelector("#consent-banner")

            const load = () => {
              if (document.getElementById("ga-script")) return
              const s = document.createElement("script")
              s.id = "ga-script"
              s.async = true
              s.src = `https://www.googletagmanager.com/gtag/js?id=${id}`
              document.head.appendChild(s)
              window.dataLayer = window.dataLayer || []
              function gtag(){ window.dataLayer.push(arguments) }
              window.gtag = gtag
              gtag("js", new Date())
              // No advertising signals, and IPs truncated: we want to know which
              // pages help, not who read them.
              gtag("config", id, { anonymize_ip: true, allow_google_signals: false })
            }

            const decide = (value) => {
              try { localStorage.setItem(key, value) } catch (_e) {}
              banner.hidden = true
              if (value === "granted") load()
            }

            let stored = null
            try { stored = localStorage.getItem(key) } catch (_e) {}

            if (stored === "granted") { load() }
            else if (stored !== "denied") { banner.hidden = false }

            this.el.querySelector("#consent-accept").addEventListener("click", () => decide("granted"))
            this.el.querySelector("#consent-decline").addEventListener("click", () => decide("denied"))
          }
        }
      </script>
    </div>
    """
  end

  defp consent_text("fr"),
    do:
      "Nous aimerions mesurer quelles pages aident les gens à passer à l'action, avec Google Analytics. Rien n'est activé tant que vous n'avez pas accepté, et refuser n'enlève aucune fonctionnalité."

  defp consent_text(_locale),
    do:
      "We would like to measure which pages help people take action, using Google Analytics. Nothing runs until you accept, and declining costs you no functionality."

  defp accept_label("fr"), do: "Accepter"
  defp accept_label(_locale), do: "Accept"

  defp decline_label("fr"), do: "Refuser"
  defp decline_label(_locale), do: "Decline"
end
