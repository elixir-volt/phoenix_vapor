/**
 * LiveVueNext — Vapor-style direct DOM patching for Phoenix LiveView.
 *
 * Replaces morphdom's tree reconciliation with targeted node writes
 * for elements rendered by LiveVueNext. On first render, builds a
 * registry mapping each dynamic slot to its DOM node. On diffs,
 * applies changes directly — one property write per changed slot.
 *
 * ## Usage
 *
 *   import { patchLiveSocket } from "live_vue_next"
 *
 *   let liveSocket = new LiveSocket("/live", Socket, { ... })
 *   patchLiveSocket(liveSocket)
 *   liveSocket.connect()
 *
 * ## How It Works
 *
 * 1. Server renders elements with `data-vapor-statics` attribute
 *    containing the JSON-encoded statics array.
 *
 * 2. On first render (join), VaporPatch parses the statics and builds
 *    a registry mapping each dynamic slot index to its DOM node + type.
 *
 * 3. On subsequent diffs, instead of going through toString → morphdom,
 *    reads the merged dynamic values from the Rendered object and applies
 *    them directly to registered DOM nodes.
 *
 * 4. Falls through to the standard morphdom path for:
 *    - Fingerprint changes (template shape changed)
 *    - Structural operations (v-if branch switch, v-for list changes)
 *    - Component diffs
 *    - Stream operations
 */

import { analyzeStatics, resolveRegistry, applyDiff } from "./vapor_patch.js"

// Per-view Vapor state
const vaporViews = new WeakMap()

/**
 * Patch a LiveSocket instance to use Vapor rendering for elements
 * with data-vapor-statics attributes.
 */
export function patchLiveSocket(liveSocket, opts = {}) {
  const debug = opts.debug || false

  // Hook into the dom callbacks to build registries on mount
  const origOnNodeAdded = liveSocket.domCallbacks.onNodeAdded
  const origOnPatchEnd = liveSocket.domCallbacks.onPatchEnd
  const origOnBeforeElUpdated = liveSocket.domCallbacks.onBeforeElUpdated

  liveSocket.domCallbacks.onNodeAdded = function(el) {
    origOnNodeAdded && origOnNodeAdded(el)
    if (el.dataset && el.dataset.vaporStatics) {
      buildVaporRegistry(el)
    }
  }

  liveSocket.domCallbacks.onBeforeElUpdated = function(fromEl, toEl) {
    if (origOnBeforeElUpdated) {
      const result = origOnBeforeElUpdated(fromEl, toEl)
      if (result === false) return false
    }

    // Intercept updates to vapor-managed elements
    const state = vaporViews.get(fromEl)
    if (!state || state.registry.size === 0) return true

    const t0 = performance.now()

    // Apply targeted updates by comparing fromEl and toEl
    let allHandled = true
    for (const [slotIdx, entry] of state.registry) {
      if (!applySlotFromMorphdom(entry, fromEl, toEl)) {
        allHandled = false
      }
    }

    if (allHandled) {
      syncControlAttrs(fromEl, toEl)
      if (debug) {
        const dt = performance.now() - t0
        window.__vaporPatchCount = (window.__vaporPatchCount || 0) + 1
        window.__vaporPatchTotalMs = (window.__vaporPatchTotalMs || 0) + dt
      }
      return false
    }

    return true
  }

  liveSocket.domCallbacks.onPatchEnd = function(container) {
    origOnPatchEnd && origOnPatchEnd(container)

    // Rebuild registries after morphdom runs (handles structural changes)
    rebuildRegistries()
  }
}

function buildVaporRegistry(el) {
  try {
    const statics = JSON.parse(el.dataset.vaporStatics)
    const slots = analyzeStatics(statics)
    const registry = resolveRegistry(slots, el)
    vaporViews.set(el, { statics, slots, registry })
  } catch (e) {
    console.warn("[LiveVueNext] Registry build failed:", e)
  }
}

function rebuildRegistries() {
  // Find all vapor elements and rebuild their registries
  document.querySelectorAll("[data-vapor-statics]").forEach(el => {
    const state = vaporViews.get(el)
    if (state) {
      state.registry = resolveRegistry(state.slots, el)
    } else {
      buildVaporRegistry(el)
    }
  })
}

function applySlotFromMorphdom(entry, fromEl, toEl) {
  switch (entry.type) {
    case "text": {
      const toNode = findCorrespondingNode(entry.node, fromEl, toEl)
      if (toNode && entry.node.nodeValue !== toNode.nodeValue) {
        entry.node.nodeValue = toNode.nodeValue
      }
      return true
    }
    case "attr": {
      if (!entry.key) return false
      const toNode = findCorrespondingElement(entry.node, fromEl, toEl)
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

function findCorrespondingNode(node, fromRoot, toRoot) {
  const path = getNodePath(node, fromRoot)
  if (!path) return null
  let target = toRoot
  for (const idx of path) {
    if (!target.childNodes[idx]) return null
    target = target.childNodes[idx]
  }
  return target
}

function findCorrespondingElement(el, fromRoot, toRoot) {
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
