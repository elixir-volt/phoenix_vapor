/**
 * LiveVueNext — Vapor-style direct DOM patching for Phoenix LiveView.
 *
 * Bypasses morphdom entirely for Vapor-managed elements. Instead of:
 *   diff → mergeDiff → toString() → innerHTML → morphdom tree walk
 *
 * Does:
 *   diff → mergeDiff → read dynamic values → single DOM write per slot
 *
 * ## Usage
 *
 *   import { patchLiveSocket } from "live_vue_next"
 *
 *   let liveSocket = new LiveSocket("/live", Socket, { ... })
 *   patchLiveSocket(liveSocket)
 *   liveSocket.connect()
 */

import { analyzeStatics, resolveRegistry, applyDiff } from "./vapor_patch.js"

// Per-element state: { statics, slots, registry }
const vaporElements = new WeakMap()

// Flag set after first view is patched
let viewPrototypePatched = false

/**
 * Patch a LiveSocket to use Vapor rendering for data-vapor-statics elements.
 *
 * Monkey-patches View.prototype.update to bypass toString+morphdom when a diff
 * only contains dynamic value changes (no structural/component changes).
 *
 * @param {LiveSocket} liveSocket
 * @param {Object} [opts]
 * @param {boolean} [opts.debug] - Enable performance counters on window
 */
export function patchLiveSocket(liveSocket, opts = {}) {
  const debug = opts.debug || false

  // Hook into dom callbacks for registry building
  const origOnNodeAdded = liveSocket.domCallbacks.onNodeAdded
  const origOnBeforeElUpdated = liveSocket.domCallbacks.onBeforeElUpdated

  liveSocket.domCallbacks.onNodeAdded = function(el) {
    origOnNodeAdded && origOnNodeAdded(el)
    if (el.dataset && el.dataset.vaporStatics) {
      buildRegistry(el)
    }
  }

  // Fallback: if the View.prototype patch misses (structural changes, etc.),
  // still optimize the morphdom walk
  liveSocket.domCallbacks.onBeforeElUpdated = function(fromEl, toEl) {
    if (origOnBeforeElUpdated) {
      const result = origOnBeforeElUpdated(fromEl, toEl)
      if (result === false) return false
    }

    const state = vaporElements.get(fromEl)
    if (!state || state.registry.size === 0) return true

    // Apply targeted updates from morphdom's toEl
    let allHandled = true
    for (const [, entry] of state.registry) {
      if (!applyFromMorphdom(entry, fromEl, toEl)) {
        allHandled = false
      }
    }

    if (allHandled) {
      syncControlAttrs(fromEl, toEl)
      return false
    }
    return true
  }

  // Build initial registries for any elements already in the DOM
  document.querySelectorAll("[data-vapor-statics]").forEach(buildRegistry)

  // Patch View.prototype.update when the first view connects.
  // We can't do this immediately because View isn't exported, so we
  // wait for a root view to appear, then patch its prototype.
  const origConnect = liveSocket.connect.bind(liveSocket)
  liveSocket.connect = function() {
    origConnect()
    waitForViews(liveSocket, debug)
  }
}

function waitForViews(liveSocket, debug) {
  if (viewPrototypePatched) return

  const check = () => {
    const rootId = Object.keys(liveSocket.roots || {})[0]
    if (!rootId) {
      requestAnimationFrame(check)
      return
    }

    const view = liveSocket.roots[rootId]
    const proto = Object.getPrototypeOf(view)

    if (proto.update && !proto.__vaporPatched) {
      patchViewPrototype(proto, debug)
    }
  }

  requestAnimationFrame(check)
}

function patchViewPrototype(proto, debug) {
  const origUpdate = proto.update
  viewPrototypePatched = true
  proto.__vaporPatched = true

  proto.update = function(diff, events, isPending) {
    // Only attempt Vapor path for simple diffs
    if (diff && !("c" in diff) && !("s" in diff)) {
      const vaporEl = this.el.querySelector("[data-vapor-statics]")
      const state = vaporEl && vaporElements.get(vaporEl)

      if (state && state.registry.size > 0) {
        // Merge diff into rendered tree (state tracking)
        this.rendered.mergeDiff(diff)

        // Read dynamic values directly from the Rendered object
        const inner = this.rendered.rendered
        let applied = 0

        for (const [slotIdx, entry] of state.registry) {
          const value = inner[slotIdx]
          if (value === null || value === undefined) continue

          const strValue = String(value)

          switch (entry.type) {
            case "text":
              if (entry.node.nodeValue !== strValue) {
                entry.node.nodeValue = strValue
                applied++
              }
              break
            case "attr":
              if (entry.key && entry.node.getAttribute(entry.key) !== strValue) {
                setAttr(entry.node, entry.key, strValue)
                applied++
              }
              break
          }
        }

        if (applied > 0 || hasOnlyKnownSlots(diff, state.registry)) {
          if (debug) {
            window.__vaporDirectPatches = (window.__vaporDirectPatches || 0) + 1
          }
          this.liveSocket.dispatchEvents(events)
          return true
        }
      }
    }

    // Fallback to original update (toString + morphdom)
    return origUpdate.call(this, diff, events, isPending)
  }
}

function hasOnlyKnownSlots(diff, registry) {
  for (const key of Object.keys(diff)) {
    const idx = parseInt(key)
    if (!isNaN(idx) && !registry.has(idx)) return false
  }
  return true
}

function buildRegistry(el) {
  try {
    const statics = JSON.parse(el.dataset.vaporStatics)
    const slots = analyzeStatics(statics)
    const registry = resolveRegistry(slots, el)
    vaporElements.set(el, { statics, slots, registry })
  } catch (e) {
    console.warn("[LiveVueNext] Registry build failed:", e)
  }
}

function applyFromMorphdom(entry, fromEl, toEl) {
  switch (entry.type) {
    case "text": {
      const toNode = findNodeByPath(entry.node, fromEl, toEl)
      if (toNode && entry.node.nodeValue !== toNode.nodeValue) {
        entry.node.nodeValue = toNode.nodeValue
      }
      return true
    }
    case "attr": {
      if (!entry.key) return false
      const toNode = findElementByPath(entry.node, fromEl, toEl)
      if (toNode) {
        const newVal = toNode.getAttribute(entry.key)
        if (newVal !== null && entry.node.getAttribute(entry.key) !== newVal) {
          setAttr(entry.node, entry.key, newVal)
        }
      }
      return true
    }
    default:
      return false
  }
}

function syncControlAttrs(fromEl, toEl) {
  for (let i = 0; i < toEl.attributes.length; i++) {
    const { name, value } = toEl.attributes[i]
    if (name.startsWith("data-phx-") || name.startsWith("phx-")) {
      if (fromEl.getAttribute(name) !== value) {
        fromEl.setAttribute(name, value)
      }
    }
  }
}

function findNodeByPath(node, fromRoot, toRoot) {
  const path = getNodePath(node, fromRoot)
  if (!path) return null
  let target = toRoot
  for (const idx of path) {
    if (!target.childNodes[idx]) return null
    target = target.childNodes[idx]
  }
  return target
}

function findElementByPath(el, fromRoot, toRoot) {
  const path = getElementPath(el, fromRoot)
  if (!path) return null
  let target = toRoot
  for (const idx of path) {
    let elemIdx = 0, found = false
    for (const child of target.childNodes) {
      if (child.nodeType === Node.ELEMENT_NODE) {
        if (elemIdx === idx) { target = child; found = true; break }
        elemIdx++
      }
    }
    if (!found) return null
  }
  return target
}

function getNodePath(node, root) {
  const path = []
  let current = node
  while (current && current !== root) {
    const parent = current.parentNode
    if (!parent) return null
    let idx = 0
    for (let i = 0; i < parent.childNodes.length; i++) {
      if (parent.childNodes[i] === current) break
      idx++
    }
    path.unshift(idx)
    current = parent
  }
  return current === root ? path : null
}

function getElementPath(el, root) {
  const path = []
  let current = el
  while (current && current !== root) {
    const parent = current.parentElement
    if (!parent) return null
    let idx = 0
    for (const child of parent.children) {
      if (child === current) break
      idx++
    }
    path.unshift(idx)
    current = parent
  }
  return current === root ? path : null
}

function setAttr(el, key, value) {
  switch (key) {
    case "class": el.className = value; break
    case "style": el.style.cssText = value; break
    case "value": el.value = value; break
    default: el.setAttribute(key, value)
  }
}

export { analyzeStatics, resolveRegistry, applyDiff } from "./vapor_patch.js"
