// Vapor-style direct DOM patching for Phoenix LiveView.
//
// For elements rendered with `data-vapor-statics`, a diff that only changes
// dynamic values is written straight to the registered nodes, instead of
// diff → toString() → innerHTML → morphdom.
//
//     import { patchLiveSocket } from "phoenix_vapor"
//
//     const liveSocket = new LiveSocket("/live", Socket, { ... })
//     patchLiveSocket(liveSocket)
//     liveSocket.connect()
//
// This relies on LiveView internals (View.prototype.update and the rendered
// tree), and falls back to LiveView's own patching when they don't match.

import {
  analyzeStatics,
  applyValue,
  elementPath,
  resolveRegistry,
  setAttribute,
  slotText,
  walkPath,
  type Diff,
  type Registry,
  type RegistryEntry
} from "./vapor-patch.ts"

export { analyzeStatics, applyDiff, resolveRegistry } from "./vapor-patch.ts"
export type { Diff, Registry, RegistryEntry, SlotDescriptor } from "./vapor-patch.ts"

type DomCallback = (...args: Element[]) => unknown

interface LiveSocketLike {
  domCallbacks: { onNodeAdded?: DomCallback; onBeforeElUpdated?: DomCallback }
  roots?: Record<string, object>
  connect(): void
}

interface ViewLike {
  el: Element
  rendered: { mergeDiff(diff: Diff): void; rendered: Record<string, unknown> }
  liveSocket: { dispatchEvents(events: unknown): void }
}

type ViewUpdate = (this: ViewLike, diff: Diff, events: unknown, isPending: unknown) => unknown

interface ViewPrototype {
  update?: ViewUpdate
  __vaporPatched?: boolean
}

export interface PatchOptions {
  /** Count direct patches in `window.__vaporDirectPatches`. */
  debug?: boolean
}

declare global {
  interface Window {
    __vaporDirectPatches?: number
  }
}

const registries = new WeakMap<Element, Registry>()

export function patchLiveSocket(liveSocket: LiveSocketLike, opts: PatchOptions = {}) {
  const { onNodeAdded, onBeforeElUpdated } = liveSocket.domCallbacks

  liveSocket.domCallbacks.onNodeAdded = (el) => {
    onNodeAdded?.(el)
    if (el instanceof HTMLElement && el.dataset.vaporStatics) buildRegistry(el)
  }

  // When the prototype patch can't handle a diff, still skip morphdom's walk
  // for elements whose slots are all registered.
  liveSocket.domCallbacks.onBeforeElUpdated = (fromEl, toEl) => {
    if (onBeforeElUpdated?.(fromEl, toEl) === false) return false

    const registry = registries.get(fromEl)
    if (!registry || registry.size === 0) return true

    for (const entry of registry.values()) {
      if (!applyFromMorphdom(entry, fromEl, toEl)) return true
    }

    syncControlAttrs(fromEl, toEl)
    return false
  }

  document.querySelectorAll<HTMLElement>("[data-vapor-statics]").forEach(buildRegistry)

  // View isn't exported, so patch its prototype once the first root view exists.
  const connect = liveSocket.connect.bind(liveSocket)
  liveSocket.connect = () => {
    connect()
    waitForRootView(liveSocket, opts.debug ?? false)
  }
}

function waitForRootView(liveSocket: LiveSocketLike, debug: boolean) {
  const check = () => {
    const view = Object.values(liveSocket.roots ?? {})[0]
    if (!view) {
      requestAnimationFrame(check)
      return
    }

    const proto = Object.getPrototypeOf(view) as ViewPrototype
    if (proto.update && !proto.__vaporPatched) patchViewPrototype(proto, proto.update, debug)
  }

  requestAnimationFrame(check)
}

function patchViewPrototype(proto: ViewPrototype, update: ViewUpdate, debug: boolean) {
  proto.__vaporPatched = true

  proto.update = function (diff, events, isPending) {
    // Structural diffs ("c" components, "s" statics) go through LiveView.
    if (diff && !("c" in diff) && !("s" in diff)) {
      const vaporEl = this.el.querySelector<HTMLElement>("[data-vapor-statics]")
      const registry = vaporEl && registries.get(vaporEl)
      // A layout nests the template's own rendered inside the view's.
      const path = registry && registry.size > 0 && renderedPath(this, vaporEl)
      const own = path && descend(diff, path)

      // Only a diff that changes nothing but registered slots is written
      // directly; anything else goes to LiveView whole.
      if (own && onlyRegisteredSlots(own, registry)) {
        this.rendered.mergeDiff(diff)
        const values = at(this.rendered.rendered, path)!

        for (const [slot, entry] of registry) {
          applyValue(entry, slot, (part) => slotText(values[part]))
        }

        if (debug) window.__vaporDirectPatches = (window.__vaporDirectPatches ?? 0) + 1
        this.liveSocket.dispatchEvents(events)
        return true
      }
    }

    return update.call(this, diff, events, isPending)
  }
}

// The slot keys from the view's rendered tree down to the one whose statics
// are the element's, remembered while they still lead there.
const paths = new WeakMap<Element, string[]>()

function renderedPath(view: ViewLike, el: HTMLElement): string[] | null {
  const root = view.rendered.rendered
  const known = paths.get(el)
  if (known && sameStatics(at(root, known), el.dataset.vaporStatics!)) return known

  const found = findStatics(root, el.dataset.vaporStatics!)
  if (found) paths.set(el, found)
  return found
}

function findStatics(rendered: Diff, statics: string): string[] | null {
  if (sameStatics(rendered, statics)) return []

  for (const [key, child] of Object.entries(rendered)) {
    // Comprehensions ("k") repeat their statics, so a template isn't in one.
    if (!/^\d+$/.test(key) || !isRendered(child) || "k" in child) continue
    const rest = findStatics(child, statics)
    if (rest) return [key, ...rest]
  }

  return null
}

// LiveView resolves shared statics in place when it renders, so a rendered
// tree that has been rendered holds each template's statics as an array.
function sameStatics(rendered: Diff | null, statics: string) {
  return Array.isArray(rendered?.s) && JSON.stringify(rendered.s) === statics
}

function at(rendered: Diff, path: string[]): Diff | null {
  let current = rendered
  for (const key of path) {
    const child = current[key]
    if (!isRendered(child)) return null
    current = child
  }
  return current
}

// The part of `diff` at `path`, when the diff changes nothing outside it and
// replaces nothing on the way.
function descend(diff: Diff, path: string[]): Diff | null {
  let current = diff
  for (const key of path) {
    const child = current[key]
    const others = Object.keys(current).some((other) => other !== key && /^\d+$/.test(other))
    if (others || !isRendered(child) || "s" in child) return null
    current = child
  }
  return current
}

function isRendered(value: unknown): value is Diff {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function onlyRegisteredSlots(diff: Diff, registry: Registry) {
  return Object.keys(diff).every((key) => {
    const slot = Number.parseInt(key, 10)
    return Number.isNaN(slot) || registry.has(slot)
  })
}

function buildRegistry(el: HTMLElement) {
  try {
    const statics = JSON.parse(el.dataset.vaporStatics!) as string[]
    const keys = JSON.parse(el.dataset.vaporKeys ?? "[]") as (string | null)[]
    registries.set(el, resolveRegistry(analyzeStatics(statics, keys), el))
  } catch (error) {
    console.warn("[PhoenixVapor] Registry build failed:", error)
  }
}

function applyFromMorphdom(entry: RegistryEntry, fromEl: Element, toEl: Element): boolean {
  if (entry.type === "text") {
    const toNode = followNodePath(toEl, nodePath(entry.node, fromEl))
    if (toNode && entry.node.nodeValue !== toNode.nodeValue) entry.node.nodeValue = toNode.nodeValue
    return true
  }

  const path = elementPath(entry.node, fromEl)
  const toNode = path && walkPath(toEl, path)
  if (toNode) setAttribute(entry.node, entry.key, toNode.getAttribute(entry.key))
  return true
}

function syncControlAttrs(fromEl: Element, toEl: Element) {
  for (const { name, value } of Array.from(toEl.attributes)) {
    if (
      (name.startsWith("data-phx-") || name.startsWith("phx-")) &&
      fromEl.getAttribute(name) !== value
    ) {
      fromEl.setAttribute(name, value)
    }
  }
}

function nodePath(node: Node, root: Node): number[] | null {
  const path: number[] = []
  let current = node
  while (current !== root) {
    const parent = current.parentNode
    if (!parent) return null
    path.unshift(Array.prototype.indexOf.call(parent.childNodes, current))
    current = parent
  }
  return path
}

function followNodePath(root: Node, path: number[] | null): Node | null {
  if (!path) return null
  let node: Node | undefined = root
  for (const index of path) {
    node = node.childNodes[index]
    if (!node) return null
  }
  return node
}
