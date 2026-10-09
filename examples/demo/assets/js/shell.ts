// The shell's switches, which belong to the page rather than to LiveView:
// the x-ray, on <html> so it survives navigation, and the theme, kept in
// localStorage and applied before paint by the root layout.

function typing(target: EventTarget | null): boolean {
  return (
    target instanceof HTMLElement &&
    (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))
  )
}

function toggleXray() {
  const root = document.documentElement
  if (root.hasAttribute("data-xray")) root.removeAttribute("data-xray")
  else root.setAttribute("data-xray", "")
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

export function installShell() {
  document.addEventListener("click", (event) => {
    const action = (event.target as Element | null)?.closest<HTMLElement>("[data-action]")?.dataset.action
    if (action === "xray") toggleXray()
    if (action === "theme") toggleTheme()
  })

  document.addEventListener("keydown", (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey || typing(event.target)) return
    if (event.key === "x") toggleXray()
  })
}
