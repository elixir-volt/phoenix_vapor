// The shell's switches, which belong to the page rather than to LiveView:
// the x-ray, on <html> so it survives navigation, and the theme, kept in
// localStorage and applied before paint by the root layout. While the x-ray
// is on, a click on a region shows its source instead of doing what it does.

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

function toggleTheme() {
  const root = document.documentElement
  const light = root.dataset.theme !== "light"
  if (light) root.dataset.theme = "light"
  else delete root.dataset.theme
  try {
    localStorage.setItem("theme", light ? "light" : "dark")
  } catch {
    // Private windows may refuse storage; the theme then lasts for the page.
  }
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
    if (action === "theme") toggleTheme()
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
