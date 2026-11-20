// Load before the application bundle so its startup failures are observable.
(() => {
  const classes = new Set(["Error", "TypeError", "ReferenceError", "SyntaxError",
    "RangeError", "SecurityError", "NetworkError"])
  const surfaces = {groups: "groups", groupes: "groups", profile: "profile",
    profil: "profile", admin: "admin", manage: "manage"}
  let remaining = 5

  function report(kind, name, line = 0) {
    const csrf = document.querySelector("meta[name='csrf-token']")?.content
    if (!csrf || remaining === 0) return
    remaining--
    const section = location.pathname.split("/").find(part => Object.hasOwn(surfaces, part))
    const payload = {
      kind,
      class: classes.has(name) ? name : "unknown",
      surface: surfaces[section] || "public",
      line
    }
    // Messages, stacks and URLs can contain volunteer details or confirmation links.
    fetch("/client-errors", {
      method: "POST", credentials: "same-origin", keepalive: true,
      headers: {"content-type": "application/json", "x-csrf-token": csrf},
      body: JSON.stringify(payload)
    }).catch(() => {})
  }

  window.addEventListener("error", event => {
    if (event.target instanceof HTMLScriptElement) report("script_load", "NetworkError")
    else if (event instanceof ErrorEvent) report("exception", event.error?.name, event.lineno)
  }, true)
  window.addEventListener("unhandledrejection", event => report("rejection", event.reason?.name))
  window.addEventListener("pauseai:connection-failed", () => report("socket_recovery", "NetworkError"))
})()
