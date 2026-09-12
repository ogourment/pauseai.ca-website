// Keep authentication capabilities and personal account pages away from gtag.
// Consent-gated success events wait for the next non-sensitive public page.
const consentKey = "pauseai-ca:analytics-consent"
const queueKey = "pauseai-ca:signup-events:v1"
const sources = ["header", "home_questions", "resource_bookmark", "home_footer", "unknown"]
const events = ["sign_up", "account_confirmed"]

export function publicAnalyticsPage(path = window.location.pathname) {
  return path === "/" || /^\/(en|fr)(\/)?$/.test(path) ||
    /^\/(en\/(learn|warning-shot|strategy|about|privacy)|fr\/(comprendre|learn|tir-de-semonce|strategie|a-propos|confidentialite))$/.test(path)
}

export function queueSignupMetric(detail) {
  try {
    if (!document.querySelector("#analytics[data-ga]") || localStorage.getItem(consentKey) !== "granted" || !events.includes(detail.event)) return
    const queue = JSON.parse(localStorage.getItem(queueKey) || "[]")
    queue.push({event: detail.event, source: sources.includes(detail.source) ? detail.source : "unknown"})
    localStorage.setItem(queueKey, JSON.stringify(queue.slice(-20)))
  } catch (_error) { /* Analytics failure must never undo account creation. */ }
}

export function flushSignupMetrics() {
  if (!publicAnalyticsPage() || !window.gtag) return
  try {
    if (localStorage.getItem(consentKey) !== "granted") return
    const queue = JSON.parse(localStorage.getItem(queueKey) || "[]")
    // Remove before sending: analytics is best-effort, never a durable email queue.
    localStorage.removeItem(queueKey)
    for (const detail of queue) {
      if (!events.includes(detail.event)) continue
      window.gtag("event", detail.event, {
        method: "email_link",
        signup_entry_point: sources.includes(detail.source) ? detail.source : "unknown",
        page_location: window.location.origin + window.location.pathname,
        page_referrer: window.location.origin,
      })
    }
  } catch (_error) {}
}

window.pauseaiSignupAnalytics = {queue: queueSignupMetric, flush: flushSignupMetrics, publicPage: publicAnalyticsPage}
window.addEventListener("phx:signup-metric", event => queueSignupMetric(event.detail))
