const anonymousKey = "pauseai-ca:learning:v1"
let key = anonymousKey
const idle = 30 * 60 * 1000
let memory = {ids: [], answers: {}, visits: 1, seen: Date.now()}
let storageAvailable = true
function read() {
  try { return {...memory, ...JSON.parse(localStorage.getItem(key) || "{}")} }
  catch (_) { storageAvailable = false; return memory }
}
function save(state) {
  memory = state
  try { localStorage.setItem(key, JSON.stringify(state)) } catch (_) { storageAvailable = false }
}
const csrf = () => document.querySelector("meta[name=csrf-token]")?.content
let pending = Promise.resolve()
function initialize() {
  const root = document.querySelector("[data-learning-root]")
  if (!root || root.dataset.initialized) return
  root.dataset.initialized = "true"
  const fr = root.dataset.locale === "fr"
  const copy = JSON.parse(root.dataset.learningCopy)
  const cards = [...root.querySelectorAll("[data-nugget]")]
  const valid = ids => Array.isArray(ids) ? [...new Set(ids.filter(id => cards.some(c => c.dataset.nugget === id)))] : []
  const anonymous = read()
  const account = root.dataset.account !== ""
  if (account) key = `${anonymousKey}:${root.dataset.accountId}`
  let state = account ? read() : anonymous
  state.ids = valid(state.ids)
  state.answers = state.answers && typeof state.answers === "object" ? state.answers : {}
  state.pending = Array.isArray(state.pending) ? state.pending.filter(change => change && ["merge", "add", "remove"].includes(change.operation)) : []
  state.visits = Number(state.visits) || 1
  if (Date.now() - state.seen > idle && performance.getEntriesByType("navigation")[0]?.type !== "reload") state.visits++
  state.seen = Date.now()
  if (account) {
    const transferred = state.transferred === root.dataset.accountId
    state.ids = valid([...JSON.parse(root.dataset.account), ...(transferred ? [] : anonymous.ids || [])])
    state.transferred = root.dataset.accountId
    for (const operation of state.pending || []) {
      state.ids = operation.operation === "remove" ? state.ids.filter(id => id !== operation.id) : valid([...state.ids, operation.id])
    }
  }
  save(state)
  function sync(operation, id) {
    if (!account) return
    const change = {operation, id, ids: [...state.ids], token: `${Date.now()}:${Math.random()}`}
    state.pending = [...(state.pending || []), change]
    save(state)
    send(change)
  }
  function send(change) {
    pending = pending.catch(() => {}).then(async () => {
      const response = await fetch("/learning/basket", {method: "POST", headers: {"content-type": "application/json", "x-csrf-token": csrf()}, body: JSON.stringify(change)})
      if (!response.ok) throw new Error("save")
      state.pending = (state.pending || []).filter(item => item.token !== change.token)
      save(state)
    }).catch(() => {root.querySelector("[data-basket-status]").textContent = copy.syncError})
  }
  function render() {
    cards.forEach(card => {
      const selected = state.ids.includes(card.dataset.nugget)
      const button = card.querySelector("[data-basket-toggle]")
      button.textContent = selected ? copy.remove : copy.add
      button.setAttribute("aria-pressed", String(selected))
    })
    const list = root.querySelector("[data-basket-list]")
    list.replaceChildren()
    state.ids.forEach(id => {
      const card = cards.find(c => c.dataset.nugget === id)
      const item = document.createElement("li")
      const link = document.createElement("a")
      link.href = `${fr ? "/fr/comprendre" : "/en/learn"}#nugget-${id}`
      link.textContent = card.dataset.nuggetTitle
      link.className = "underline"
      const remove = document.createElement("button")
      remove.type = "button"; remove.className = "ml-4 underline"; remove.textContent = copy.removeShort
      remove.setAttribute("aria-label", `${remove.textContent}: ${link.textContent}`)
      remove.addEventListener("click", () => toggle(id))
      item.append(link, remove); list.append(item)
    })
    root.querySelector("[data-basket-status]").textContent = state.ids.length ? `${copy.count} ${state.ids.length}` : copy.empty
    root.querySelector("[data-learning-storage-warning]").classList.toggle("hidden", storageAvailable)
    root.querySelector("[data-return-invitation]").classList.toggle("hidden", account || state.visits < 2 || !!state.dismissed)
    document.querySelectorAll('a[href*="/users/register"]').forEach(link => {
      const url = new URL(link.href)
      url.searchParams.set("basket", state.ids.join(","))
      url.searchParams.set("locale", root.dataset.locale)
      url.searchParams.set("return_to", fr ? "/fr/comprendre" : "/en/learn")
      link.href = url.pathname + url.search
    })
  }
  function toggle(id) {
    const removing = state.ids.includes(id)
    state.ids = removing ? state.ids.filter(value => value !== id) : [...state.ids, id]
    save(state); render(); sync(removing ? "remove" : "add", id)
  }
  cards.forEach(card => {
    card.querySelector("[data-basket-toggle]").addEventListener("click", () => toggle(card.dataset.nugget))
    function answer(value) {
      card.querySelectorAll("[data-quiz-answer]").forEach(button => button.setAttribute("aria-pressed", String(button.dataset.quizAnswer === value)))
      card.querySelector("[data-explanation]").open = true
      const feedback = card.querySelector("[data-quiz-feedback]")
      if (feedback) feedback.textContent = value === "unknown" ? copy.unknown : value === "0" ? copy.correct : copy.incorrect
    }
    card.querySelectorAll("[data-quiz-answer]").forEach(button => button.addEventListener("click", () => {state.answers[card.dataset.nugget] = button.dataset.quizAnswer; save(state); answer(button.dataset.quizAnswer)}))
    if (state.answers[card.dataset.nugget] !== undefined) answer(state.answers[card.dataset.nugget])
  })
  root.querySelector("[data-dismiss-return]")?.addEventListener("click", () => {state.dismissed = true; save(state); render()})
  render()
  if (account) {
    const previous = [...(state.pending || [])]
    previous.forEach(send)
    sync("merge")
  }
  const heartbeat = setInterval(() => {
    if (!root.isConnected) {clearInterval(heartbeat); return}
    if (document.visibilityState === "visible") {state.seen = Date.now(); save(state)}
  }, 60 * 1000)
  window.addEventListener("storage", event => {if (event.key === key) {state = read(); state.ids = valid(state.ids); render()}})
}
initialize()
document.addEventListener("DOMContentLoaded", initialize)
window.addEventListener("phx:page-loading-stop", initialize)
// Preserve the current list even when a LiveView has just inserted a new link.
document.addEventListener("click", event => {
  const link = event.target.closest('a[href*="/users/register"]')
  const root = document.querySelector("[data-learning-root]")
  if (!link || !root) return
  const url = new URL(link.href)
  url.searchParams.set("basket", (read().ids || []).join(","))
  url.searchParams.set("locale", root.dataset.locale)
  url.searchParams.set("return_to", root.dataset.locale === "fr" ? "/fr/comprendre" : "/en/learn")
  link.href = url.pathname + url.search
}, true)
