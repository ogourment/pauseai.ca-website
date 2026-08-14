// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/pauseai_ca"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

const beliefStorageKey = "pauseai-ca:beliefs:v1"

function initializeBeliefCheck() {
  const check = document.querySelector("#belief-check")
  if (!check || check.dataset.initialized === "true") return

  check.dataset.initialized = "true"
  const status = document.querySelector("#local-status")
  const explanation = document.querySelector("#path-explanation")
  const locale = check.dataset.locale || "en"
  let answers = {}

  try {
    answers = JSON.parse(localStorage.getItem(beliefStorageKey) || "{}")
  } catch (_error) {
    answers = {}
  }

  const renderAnswers = () => {
    check.querySelectorAll(".belief-question").forEach(question => {
      const selected = answers[question.dataset.question]
      question.querySelectorAll("[data-answer]").forEach(button => {
        const active = button.dataset.answer === selected
        button.classList.toggle("is-selected", active)
        button.setAttribute("aria-pressed", active ? "true" : "false")
      })
    })
    const complete = ["risk", "pause", "coordination"].every(key => answers[key] !== undefined)
    document.querySelector("#save-progress-invitation")?.classList.toggle("hidden", !complete)
    const saveLink = document.querySelector("#save-question-progress")
    if (saveLink && complete) {
      const params = new URLSearchParams({from: "questions", ...answers})
      saveLink.href = `/users/register?${params.toString()}`
    }
  }

  const saveAnswers = () => {
    localStorage.setItem(beliefStorageKey, JSON.stringify(answers))
    status.textContent = locale === "fr" ? "Réponse enregistrée." : "Answer saved."
  }

  const recordAnswer = question => {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const complete = ["risk", "pause", "coordination"].every(key => answers[key] !== undefined)

    fetch(`/learning/questions/${question}`, {
      method: "POST",
      headers: {"content-type": "application/json", "x-csrf-token": csrfToken},
      keepalive: true,
      body: JSON.stringify({answer: answers[question], complete})
    }).catch(() => {})
  }

  check.querySelectorAll(".belief-question").forEach(question => {
    question.querySelectorAll("[data-answer]").forEach(button => {
      button.addEventListener("click", () => {
        answers[question.dataset.question] = button.dataset.answer
        renderAnswers()
        saveAnswers()
        recordAnswer(question.dataset.question)
      })
    })
  })

  document.querySelector("#reset-beliefs")?.addEventListener("click", () => {
    answers = {}
    localStorage.removeItem(beliefStorageKey)
    renderAnswers()
    document.querySelectorAll(".resource-card").forEach(card => card.classList.remove("is-recommended"))
    document.querySelector("#save-progress-invitation")?.classList.add("hidden")
    status.textContent = locale === "fr" ? "Réponses effacées." : "Answers cleared."
  })

  document.querySelector("#show-path")?.addEventListener("click", () => {
    const scored = Object.fromEntries(
      Object.entries(answers).map(([key, value]) => [key, Number.parseInt(value, 10)])
    )

    let recommendation = "resource-risk"
    let reason = locale === "fr"
      ? "Commencez par les raisons pour lesquelles certains chercheurs prennent le risque existentiel au sérieux."
      : "Start with why some researchers take existential risk seriously."

    if ((scored.risk || 0) >= 4 && (scored.pause || 0) < 4) {
      recommendation = "resource-pause"
      reason = locale === "fr"
        ? "Vous semblez surtout vouloir tester si une pause est une réponse utile et bien définie."
        : "You seem most interested in testing whether a pause is a useful, well-defined response."
    } else if ((scored.risk || 0) >= 4 && (scored.pause || 0) >= 4 && (scored.coordination || 0) < 4) {
      recommendation = "resource-coordination"
      reason = locale === "fr"
        ? "La question clé semble être la vérification, la conformité et l’application d’un accord."
        : "The key question appears to be verification, compliance, and enforcement."
    } else if ((scored.risk || 0) >= 4 && (scored.pause || 0) >= 4 && (scored.coordination || 0) >= 4) {
      recommendation = "resource-agency"
      reason = locale === "fr"
        ? "Vous connaissez peut-être déjà les arguments centraux; voici pourquoi l’organisation citoyenne peut compter."
        : "You may already accept the central case; here is why civic organizing can matter."
    }

    document.querySelectorAll(".resource-card").forEach(card => {
      card.classList.toggle("is-recommended", card.id === recommendation)
    })
    explanation.textContent = reason
    document.querySelector(`#${recommendation}`)?.scrollIntoView({behavior: "smooth", block: "center"})
  })

  renderAnswers()
}

document.addEventListener("DOMContentLoaded", initializeBeliefCheck)
window.addEventListener("phx:page-loading-stop", initializeBeliefCheck)
initializeBeliefCheck()

document.addEventListener("keydown", event => {
  if (event.key !== "Escape") return
  const details = document.querySelector("#learning-breakdown[open]")
  if (!details) return

  details.removeAttribute("open")
  details.querySelector("summary")?.focus()
})

document.addEventListener("click", event => {
  const details = document.querySelector("#learning-breakdown[open]")
  if (details && !details.contains(event.target)) details.removeAttribute("open")
})

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

// A <details> dropdown stays open until its own summary is clicked again, which
// is not what anyone expects from a menu. Close it on an outside click, on
// Escape, and when another one opens.
//
// Delegated from the document rather than bound per-element: the header is
// rendered by both LiveViews and plain controllers, and LiveView replaces the
// DOM underneath us on navigation.
document.addEventListener("click", (event) => {
  document.querySelectorAll("details.act-menu[open]").forEach((menu) => {
    if (!menu.contains(event.target)) menu.open = false
  })
})

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return
  document.querySelectorAll("details.act-menu[open]").forEach((menu) => {
    menu.open = false
    menu.querySelector("summary")?.focus()
  })
})

// Opening one menu closes any other.
document.addEventListener("toggle", (event) => {
  const opened = event.target
  if (!(opened instanceof HTMLDetailsElement) || !opened.open) return
  if (!opened.classList.contains("act-menu")) return

  document.querySelectorAll("details.act-menu[open]").forEach((menu) => {
    if (menu !== opened) menu.open = false
  })
}, true)
