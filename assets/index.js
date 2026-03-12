/**
 * LiveVueNext — Vapor-style direct DOM patching for Phoenix LiveView.
 *
 * Replaces morphdom's tree reconciliation with targeted node writes
 * for elements managed by LiveVueNext. On first render, builds a
 * registry mapping each dynamic slot to its DOM node. On updates,
 * applies changes directly — one property write per changed slot.
 *
 * ## Integration (no LiveView fork required)
 *
 * Uses `dom.onBeforeElUpdated` to intercept morphdom updates.
 * When morphdom tries to update a Vapor-managed root element,
 * we apply targeted updates and return false to skip the tree walk.
 *
 * ```js
 * import { createVaporDom } from "live_vue_next"
 *
 * let liveSocket = new LiveSocket("/live", Socket, {
 *   dom: createVaporDom()
 * })
 * ```
 *
 * ## Server-Side
 *
 * LiveVueNext renders mark their root elements with `data-vapor`
 * and `data-vapor-statics` attributes containing the JSON-encoded
 * statics array. This enables the client to build the node registry
 * without any server-side changes to the diff protocol.
 */

import { analyzeStatics, resolveRegistry, applyDiff } from "./vapor_patch.js"

// Cache: element ID → { registry, statics, slots }
const vaporElements = new Map()

/**
 * Create a dom callbacks object for LiveSocket that enables Vapor patching.
 *
 * @param {Object} [userDom] - User's own dom callbacks (will be called alongside Vapor)
 * @returns {Object} dom callbacks for LiveSocket constructor
 */
export function createVaporDom(userDom = {}) {
  return {
    ...userDom,

    onBeforeElUpdated(fromEl, toEl) {
      // Let user callback run first
      if (userDom.onBeforeElUpdated) {
        const result = userDom.onBeforeElUpdated(fromEl, toEl)
        if (result === false) return false
      }

      // Only intercept Vapor-managed elements
      if (!fromEl.dataset || !fromEl.dataset.vapor) return true

      const cache = vaporElements.get(fromEl.id)
      if (!cache || cache.registry.size === 0) {
        // First time or registry not built — let morphdom handle it,
        // then build the registry on next pass
        tryBuildRegistry(fromEl)
        return true
      }

      // Extract dynamic values by comparing fromEl and toEl
      // morphdom has already parsed toEl from innerHTML, so we diff against it
      let allHandled = true

      for (const [slotIdx, entry] of cache.registry) {
        switch (entry.type) {
          case "text": {
            const toNode = findCorrespondingNode(entry.node, fromEl, toEl)
            if (toNode && entry.node.nodeValue !== toNode.nodeValue) {
              entry.node.nodeValue = toNode.nodeValue
            }
            break
          }
          case "attr": {
            if (!entry.key) { allHandled = false; break }
            const toNode = findCorrespondingElement(entry.node, fromEl, toEl)
            if (toNode) {
              const newVal = toNode.getAttribute(entry.key)
              if (newVal !== null && el.getAttribute(entry.key) !== newVal) {
                applyAttr(entry.node, entry.key, newVal)
              }
            }
            break
          }
          default:
            allHandled = false
        }
      }

      if (allHandled) {
        // Sync LiveView control attributes
        syncLiveViewAttrs(fromEl, toEl)
        return false // skip morphdom tree walk
      }

      return true // fallback to morphdom
    },

    onNodeAdded(el) {
      if (userDom.onNodeAdded) userDom.onNodeAdded(el)

      // Auto-build registry for newly added Vapor elements
      if (el.dataset && el.dataset.vapor) {
        tryBuildRegistry(el)
      }
    },

    onPatchEnd(container) {
      if (userDom.onPatchEnd) userDom.onPatchEnd(container)

      // Rebuild registries for any Vapor elements that were updated
      // (handles the case where morphdom ran and changed the DOM structure)
      for (const [id, cache] of vaporElements) {
        const el = document.getElementById(id)
        if (el) {
          cache.registry = resolveRegistry(cache.slots, el)
        } else {
          vaporElements.delete(id)
        }
      }
    }
  }
}

function tryBuildRegistry(el) {
  const staticsJSON = el.dataset.vaporStatics
  if (!staticsJSON) return

  try {
    const statics = JSON.parse(staticsJSON)
    const slots = analyzeStatics(statics)
    const registry = resolveRegistry(slots, el)
    vaporElements.set(el.id, { statics, slots, registry })
  } catch (e) {
    console.warn("[LiveVueNext] Failed to build Vapor registry:", e)
  }
}

function syncLiveViewAttrs(fromEl, toEl) {
  for (let i = 0; i < toEl.attributes.length; i++) {
    const attr = toEl.attributes[i]
    if (attr.name.startsWith("data-phx-") || attr.name.startsWith("phx-")) {
      if (fromEl.getAttribute(attr.name) !== attr.value) {
        fromEl.setAttribute(attr.name, attr.value)
      }
    }
  }
}

function findCorrespondingNode(node, fromRoot, toRoot) {
  const path = getNodePathFromRoot(node, fromRoot)
  if (!path) return null
  return walkNodePath(toRoot, path)
}

function findCorrespondingElement(el, fromRoot, toRoot) {
  const path = getElementPathFromRoot(el, fromRoot)
  if (!path) return null

  let node = toRoot
  for (const idx of path) {
    let elemIdx = 0
    let found = false
    for (let i = 0; i < node.childNodes.length; i++) {
      if (node.childNodes[i].nodeType === Node.ELEMENT_NODE) {
        if (elemIdx === idx) { node = node.childNodes[i]; found = true; break }
        elemIdx++
      }
    }
    if (!found) return null
  }
  return node
}

function getElementPathFromRoot(el, root) {
  const path = []
  let current = el
  while (current && current !== root) {
    const parent = current.parentElement
    if (!parent) return null
    let idx = 0
    for (let i = 0; i < parent.children.length; i++) {
      if (parent.children[i] === current) break
      idx++
    }
    path.unshift(idx)
    current = parent
  }
  return current === root ? path : null
}

function getNodePathFromRoot(node, root) {
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

function walkNodePath(root, path) {
  let node = root
  for (const idx of path) {
    if (!node.childNodes[idx]) return null
    node = node.childNodes[idx]
  }
  return node
}

function applyAttr(el, key, value) {
  switch (key) {
    case "class": el.className = value; break
    case "style": el.style.cssText = value; break
    case "value": el.value = value; break
    default: el.setAttribute(key, value)
  }
}

export { analyzeStatics, resolveRegistry, applyDiff } from "./vapor_patch.js"
