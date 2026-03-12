/**
 * VaporPatch — Targeted DOM updates from LiveView statics analysis.
 *
 * Builds a registry mapping each dynamic slot to its DOM node by parsing
 * the statics array (the unchanging HTML fragments from %Rendered{}).
 *
 * On update, applies changes directly to registered nodes — a single
 * property write per changed slot instead of morphdom's full tree walk.
 */

const VOID_ELEMENTS = new Set([
  "area", "base", "br", "col", "embed", "hr", "img", "input",
  "link", "meta", "param", "source", "track", "wbr"
])

/**
 * Analyze the statics context to classify each dynamic slot.
 *
 * Returns an array of slot descriptors:
 *   { type: "text", parentPath: number[], textIndex: number }
 *   { type: "attr", nodePath: number[], key: string }
 */
export function analyzeStatics(statics) {
  if (!statics || statics.length <= 1) return []

  const slots = []

  for (let i = 0; i < statics.length - 1; i++) {
    const prefix = statics.slice(0, i + 1).join("")
    const context = classifySlotContext(prefix)

    if (context.type === "attr") {
      slots.push({
        type: "attr",
        nodePath: buildElementPath(prefix),
        key: context.key
      })
    } else {
      const { parentPath, textIndex } = findTextSlotPosition(statics, i, prefix)
      slots.push({
        type: "text",
        parentPath,
        textIndex
      })
    }
  }

  return slots
}

/**
 * Resolve analyzed slot descriptors against a live DOM root.
 * Returns a Map<slotIndex, {type, node, key?}>
 */
export function resolveRegistry(slots, rootEl) {
  const registry = new Map()

  for (let i = 0; i < slots.length; i++) {
    const slot = slots[i]
    let node

    if (slot.type === "attr") {
      node = walkPath(rootEl, slot.nodePath)
      if (node) {
        registry.set(i, { type: "attr", node, key: slot.key })
      }
    } else if (slot.type === "text") {
      const parent = walkPath(rootEl, slot.parentPath)
      if (parent) {
        const textNode = getTextNodeAt(parent, slot.textIndex)
        if (textNode) {
          registry.set(i, { type: "text", node: textNode })
        }
      }
    }
  }

  return registry
}

/**
 * Apply a diff to registered DOM nodes.
 */
export function applyDiff(registry, diff) {
  let applied = 0

  for (const [slotIdx, entry] of registry) {
    const key = String(slotIdx)
    if (!(key in diff)) continue

    const value = diff[key]
    // null means "unchanged" in LiveView protocol
    if (value === null || value === undefined) continue
    // nested objects are components/rendered structs — skip for now
    if (typeof value === "object") continue

    const strValue = String(value)

    switch (entry.type) {
      case "text":
        if (entry.node.nodeValue !== strValue) {
          entry.node.nodeValue = strValue
          applied++
        }
        break

      case "attr":
        if (applyAttribute(entry.node, entry.key, strValue)) {
          applied++
        }
        break
    }
  }

  return applied
}

function applyAttribute(el, key, value) {
  if (!key) return false

  switch (key) {
    case "class":
      if (el.className !== value) { el.className = value; return true }
      return false
    case "style":
      if (el.style.cssText !== value) { el.style.cssText = value; return true }
      return false
    case "value":
      if (el.value !== value) { el.value = value; return true }
      return false
    case "checked":
      { const bool = value === "true" || value === "checked"
        if (el.checked !== bool) { el.checked = bool; return true }
        return false }
    case "disabled":
      { const bool = value === "true" || value === "disabled" || value === ""
        if (el.disabled !== bool) { el.disabled = bool; return true }
        return false }
    default:
      if (el.getAttribute(key) !== value) {
        el.setAttribute(key, value)
        return true
      }
      return false
  }
}

/**
 * Determine if the dynamic slot is inside a tag attribute or in text content.
 */
function classifySlotContext(prefix) {
  for (let i = prefix.length - 1; i >= 0; i--) {
    const ch = prefix[i]
    if (ch === ">") return { type: "text" }
    if (ch === "<") {
      const attrMatch = prefix.match(/[\s]([\w\-:@.]+)\s*=\s*["']?$/)
      return { type: "attr", key: attrMatch ? attrMatch[1] : null }
    }
  }
  return { type: "text" }
}

/**
 * Build a path of child-element indices from root to the last opened element
 * in the prefix HTML.
 */
function buildElementPath(prefix) {
  const path = []
  const stack = [] // each entry: { childCount: number }
  let i = 0

  while (i < prefix.length) {
    if (prefix[i] !== "<") { i++; continue }

    if (prefix[i + 1] === "/") {
      // Closing tag
      const end = prefix.indexOf(">", i)
      if (end === -1) break
      stack.pop()
      i = end + 1
      continue
    }

    if (prefix[i + 1] === "!") { // comment
      const end = prefix.indexOf("-->", i)
      i = end === -1 ? i + 1 : end + 3
      continue
    }

    // Opening tag
    const tagMatch = prefix.slice(i).match(/^<([a-zA-Z][a-zA-Z0-9-]*)/)
    if (!tagMatch) { i++; continue }

    const tagName = tagMatch[1]

    // Count as child of parent
    if (stack.length > 0) {
      const parent = stack[stack.length - 1]
      path.splice(stack.length - 1)
      path.push(parent.childCount)
      parent.childCount++
    }

    // Find end of opening tag (handling quoted attributes)
    let j = i + tagMatch[0].length
    let inQuote = false, quoteChar = ""
    while (j < prefix.length) {
      if (inQuote) {
        if (prefix[j] === quoteChar) inQuote = false
      } else {
        if (prefix[j] === '"' || prefix[j] === "'") { inQuote = true; quoteChar = prefix[j] }
        else if (prefix[j] === ">") break
      }
      j++
    }

    const selfClosing = prefix[j - 1] === "/" || VOID_ELEMENTS.has(tagName.toLowerCase())

    if (!selfClosing) {
      stack.push({ childCount: 0 })
    } else if (stack.length > 0) {
      // Self-closing doesn't push to stack but was already counted
    }

    i = j + 1
  }

  // The path should lead to the currently open element
  // Trim to the current stack depth
  return path.slice(0, stack.length - 1)
}

/**
 * Find the text slot's parent element path and text node index within that parent.
 */
function findTextSlotPosition(statics, slotIdx, prefix) {
  const parentPath = buildElementPath(prefix)

  // Count how many text slots precede this one inside the same parent
  let textIndex = 0

  // Count text nodes that come from static content between tags
  // In the prefix, after the last ">", there may be static text before our slot
  const afterLastTag = prefix.match(/>([^<]*)$/)
  if (afterLastTag && afterLastTag[1].length > 0) {
    // There's static text before this slot — our dynamic is a continuation
    // or adjacent text node. In DOM, static text + dynamic text may merge
    // into one text node or be separate depending on how innerHTML parses.
    // With LiveView's toString, they're concatenated into one string,
    // so innerHTML creates merged text nodes.
    // We need to account for this: the text node index is based on
    // child nodes in the actual DOM.
    textIndex = countTextNodes(prefix)
  }

  // Count prior dynamic text slots inside the same parent
  for (let i = 0; i < slotIdx; i++) {
    const prevPrefix = statics.slice(0, i + 1).join("")
    const prevContext = classifySlotContext(prevPrefix)
    if (prevContext.type === "text") {
      const prevParentPath = buildElementPath(prevPrefix)
      if (pathsEqual(prevParentPath, parentPath)) {
        textIndex++
      }
    }
  }

  return { parentPath, textIndex }
}

function countTextNodes(prefix) {
  // Count distinct text segments between tags inside the last opened element
  // This is approximate — we count > ... < transitions
  let count = 0
  let afterTag = false
  for (let i = prefix.length - 1; i >= 0; i--) {
    if (prefix[i] === "<") break
    if (prefix[i] === ">") { afterTag = true; break }
  }
  // If there's text after the last >, that creates a text node
  if (afterTag) {
    const tail = prefix.match(/>([^<]+)$/)
    if (tail && tail[1].trim().length > 0) count = 1
  }
  return count
}

function pathsEqual(a, b) {
  if (a.length !== b.length) return false
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false
  }
  return true
}

/**
 * Walk from root element following a path of child-element indices.
 */
function walkPath(rootEl, path) {
  let node = rootEl
  for (const childIdx of path) {
    let elementIdx = 0
    let found = false
    for (let i = 0; i < node.childNodes.length; i++) {
      const child = node.childNodes[i]
      if (child.nodeType === Node.ELEMENT_NODE) {
        if (elementIdx === childIdx) {
          node = child
          found = true
          break
        }
        elementIdx++
      }
    }
    if (!found) return null
  }
  return node
}

/**
 * Get the nth text node child of an element.
 */
function getTextNodeAt(parent, index) {
  let textIdx = 0
  for (let i = 0; i < parent.childNodes.length; i++) {
    const child = parent.childNodes[i]
    if (child.nodeType === Node.TEXT_NODE) {
      if (textIdx === index) return child
      textIdx++
    }
  }
  return null
}
