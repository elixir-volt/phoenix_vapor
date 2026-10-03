// Direct DOM updates for Vapor-rendered LiveView elements.
//
// `analyzeStatics` finds the DOM position of every dynamic slot in a
// `%Rendered{}` statics array, `resolveRegistry` maps those positions to live
// nodes, and `applyDiff` writes a LiveView diff straight to them: one property
// write per changed slot instead of a morphdom walk.

export type SlotDescriptor =
  | { type: "text"; parentPath: number[]; textIndex: number }
  | { type: "attr"; nodePath: number[]; key: string }
  | { type: "unknown" }

export type RegistryEntry =
  | { type: "text"; node: Text }
  | { type: "attr"; node: Element; key: string }

export type Registry = Map<number, RegistryEntry>

export type Diff = Record<string, unknown>

// U+2063 (invisible separator) keeps markers out of the way of real content.
const MARKER = /⁣pv(\d+)⁣/g

function marker(index: number) {
  return `⁣pv${index}⁣`
}

function markerIndices(value: string): number[] {
  return Array.from(value.matchAll(MARKER), (match) => Number(match[1]))
}

// Paths count element children only.
export function elementPath(el: Element, root: Element): number[] | null {
  const path: number[] = []
  let current: Element = el

  while (current !== root) {
    const parent = current.parentElement
    if (!parent) return null
    path.unshift(Array.prototype.indexOf.call(parent.children, current))
    current = parent
  }

  return path
}

function textIndex(node: Text): number {
  let index = 0
  for (const child of Array.from(node.parentNode!.childNodes)) {
    if (child === node) return index
    if (child.nodeType === Node.TEXT_NODE) index++
  }
  return -1
}

/**
 * Locates each dynamic slot by parsing the statics joined with slot markers
 * and finding where the HTML parser put each marker. Paths are relative to the
 * first element, the one that carries `data-vapor-statics`.
 *
 * `keys` names the attribute each attribute slot renders, from
 * `data-vapor-keys`; the slot is the whole attribute, so its marker parses as
 * an attribute name.
 */
export function analyzeStatics(statics: string[], keys: (string | null)[] = []): SlotDescriptor[] {
  if (statics.length <= 1) return []

  const template = document.createElement("template")
  template.innerHTML = statics
    .map((part, i) => {
      if (i === statics.length - 1) return part
      return keys[i] ? `${part} ${marker(i)}` : part + marker(i)
    })
    .join("")

  const root = template.content.firstElementChild
  const slots: SlotDescriptor[] = Array.from({ length: statics.length - 1 }, () => ({
    type: "unknown"
  }))
  if (!root) return slots

  const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT)

  for (let node: Node | null = root; node; node = walker.nextNode()) {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node as Text
      const parentPath = elementPath(text.parentElement!, root)
      if (!parentPath) continue

      for (const i of markerIndices(text.data)) {
        slots[i] = { type: "text", parentPath, textIndex: textIndex(text) }
      }
    } else {
      const el = node as Element
      const nodePath = elementPath(el, root)!

      for (const attr of Array.from(el.attributes)) {
        for (const i of markerIndices(attr.name)) {
          const key = keys[i]
          if (key) slots[i] = { type: "attr", nodePath, key }
        }
      }
    }
  }

  return slots
}

/** Resolves slot descriptors against a live root element. */
export function resolveRegistry(slots: SlotDescriptor[], rootEl: Element): Registry {
  const registry: Registry = new Map()

  slots.forEach((slot, i) => {
    if (slot.type === "attr") {
      const node = walkPath(rootEl, slot.nodePath)
      if (node) registry.set(i, { type: "attr", node, key: slot.key })
    } else if (slot.type === "text") {
      const parent = walkPath(rootEl, slot.parentPath)
      const node = parent && getTextNodeAt(parent, slot.textIndex)
      if (node) registry.set(i, { type: "text", node })
    }
  })

  return registry
}

/** Applies a diff to registered nodes and returns how many changed. */
export function applyDiff(registry: Registry, diff: Diff): number {
  let applied = 0

  for (const [slotIdx, entry] of registry) {
    const value = slotText(diff[String(slotIdx)])
    if (value !== null && applyValue(entry, value)) applied++
  }

  return applied
}

/**
 * The text of a slot value, or null when there is nothing to write: null and
 * undefined mean unchanged, and objects are nested renders left to LiveView.
 */
export function slotText(value: unknown): string | null {
  switch (typeof value) {
    case "string":
      return value
    case "number":
    case "boolean":
      return String(value)
    default:
      return null
  }
}

export function applyValue(entry: RegistryEntry, value: string): boolean {
  if (entry.type === "text") {
    if (entry.node.nodeValue === value) return false
    entry.node.nodeValue = value
    return true
  }

  return setAttribute(entry.node, entry.key, attributeValue(entry.key, value))
}

/**
 * The value an attribute slot renders, such as ` class="a"`, read with the
 * browser's HTML parser. Null when the slot leaves the attribute out.
 */
export function attributeValue(key: string, rendered: string): string | null {
  if (rendered === "") return null

  const template = document.createElement("template")
  template.innerHTML = `<i${rendered}></i>`
  return template.content.firstElementChild?.getAttribute(key) ?? null
}

/** Sets an attribute, or removes it when `value` is null. */
export function setAttribute(el: Element, key: string, value: string | null): boolean {
  const html = el as HTMLInputElement

  switch (key) {
    case "class":
      if (el.className === (value ?? "")) return false
      el.className = value ?? ""
      return true
    case "style":
      if (html.style.cssText === (value ?? "")) return false
      html.style.cssText = value ?? ""
      return true
    case "value":
      if (html.value === (value ?? "")) return false
      html.value = value ?? ""
      return true
    case "checked":
    case "disabled":
      // A boolean attribute is set by being present, whatever its value.
      return setBoolean(html, key, value !== null)
    default:
      if (el.getAttribute(key) === value) return false
      if (value === null) el.removeAttribute(key)
      else el.setAttribute(key, value)
      return true
  }
}

function setBoolean(el: HTMLInputElement, key: "checked" | "disabled", value: boolean) {
  if (el[key] === value) return false
  el[key] = value
  return true
}

export function walkPath(rootEl: Element, path: number[]): Element | null {
  let node: Element | undefined = rootEl
  for (const index of path) {
    node = node.children[index]
    if (!node) return null
  }
  return node
}

function getTextNodeAt(parent: Element, index: number): Text | null {
  let textIdx = 0
  for (const child of Array.from(parent.childNodes)) {
    if (child.nodeType === Node.TEXT_NODE) {
      if (textIdx === index) return child as Text
      textIdx++
    }
  }
  return null
}
