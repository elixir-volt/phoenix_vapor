// The shell's switches, which belong to the page rather than to LiveView:
// the x-ray, on <html> so it survives navigation; while it's on, a click on a
// region shows its source instead of doing what it does. The theme is the
// server's (VaporDemoWeb.Theme); this applies a change at once and keeps it
// in the cookie for the next page load.

function typing(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))
  )
}

function xrayOn(): boolean {
  return document.documentElement.hasAttribute("data-xray")
}

function toggleXray() {
  const root = document.documentElement
  if (xrayOn()) root.removeAttribute("data-xray")
  else root.setAttribute("data-xray", "")
  if (!xrayOn()) closeSource()
}

function sourcePanel() {
  return document.getElementById("xray-source")
}

async function showSource(path: string) {
  const panel = sourcePanel()
  if (!panel) return

  panel.querySelector("[data-path]")!.textContent = path
  panel.querySelector("[data-source]")!.textContent = "Loading…"
  panel.hidden = false

  const response = await fetch(`/source/${path}`)
  panel.querySelector("[data-source]")!.textContent = response.ok
    ? await response.text()
    : `Couldn't load ${path}.`
}

function closeSource() {
  const panel = sourcePanel()
  if (panel) panel.hidden = true
}

export function installShell() {
  window.addEventListener("phx:theme", (event) => {
    const { theme } = (event as CustomEvent<{ theme: string }>).detail
    document.documentElement.dataset.theme = theme
    document.cookie = `theme=${theme}; path=/; max-age=31536000; samesite=lax`
  })

  // Capturing, so an x-rayed region's own handlers don't run.
  document.addEventListener(
    "click",
    (event) => {
      const target = event.target as Element | null
      if (!xrayOn() || !target || target.closest("[data-action], #xray-source, .xray-legend")) return

      const region = target.closest<HTMLElement>("[data-render-source]")
      if (!region) return

      event.preventDefault()
      event.stopPropagation()
      void showSource(region.dataset.renderSource!)
    },
    true
  )

  document.addEventListener("click", (event) => {
    const action = (event.target as Element | null)?.closest<HTMLElement>("[data-action]")?.dataset.action
    if (action === "xray") toggleXray()
    if (action === "close-source") closeSource()
    // The palette is a hybrid component of its own; it listens for this.
    if (action === "palette") window.dispatchEvent(new Event("palette:open"))
  })

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeSource()
    if (event.metaKey || event.ctrlKey || event.altKey || typing(event.target)) return
    if (event.key === "x") toggleXray()
  })
}
