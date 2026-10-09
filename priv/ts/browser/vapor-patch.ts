// Direct DOM updates for Vapor-rendered LiveView elements.
//
// `analyzeStatics` finds the DOM position of every dynamic slot in a
// `%Rendered{}` statics array, `resolveRegistry` maps those positions to live
// nodes, and `applyDiff` writes a LiveView diff straight to them: one property
// write per changed slot instead of a morphdom walk.

/** Static text, or the index of a slot, in a text node's content. */
export type TextPart = string | number

export type SlotDescriptor =
  | { type: "text"; parentPath: number[]; textIndex: number; parts: TextPart[] }
  | { type: "attr"; nodePath: number[]; key: string }
  | { type: "unknown" }

export type RegistryEntry =
  | { type: "text"; node: Text; parts: TextPart[] }
  | { type: "attr"; node: Element; key: string }

/** A slot's current rendered value, or null when it isn't known. */
export type SlotValues = (slot: number) => string | null

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

// A text node's content as static text and slot indices, in order.
function textParts(data: string): TextPart[] {
  const parts: TextPart[] = []
  let last = 0

  for (const match of data.matchAll(MARKER)) {
    if (match.index > last) parts.push(data.slice(last, match.index))
    parts.push(Number(match[1]))
    last = match.index + match[0].length
  }

  if (last < data.length) parts.push(data.slice(last))
  return parts
}

// A block slot (keyed `false`), such as a `v-if` branch or a component,
// parses as its marker's text but renders as many nodes as its content has.
// Each parent's block markers, in order, by the parent.
type Blocks = Map<Element, Node[]>

// A node's index among `siblings`, counted from the start when no block
// precedes it, and from the end, as a negative index, when none follows: a
// block shifts what follows it, but not how many follow. Between two blocks,
// null: its place depends on what they render.
function siblingIndex(node: Node, siblings: Node[], markers: Node[] | undefined): number | null {
  const index = siblings.indexOf(node)
  if (!markers) return index

  const follows = (a: Node, b: Node) =>
    (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0
  const afterBlock = markers.some((marker) => follows(marker, node))
  const beforeBlock = markers.some((marker) => follows(node, marker))

  if (!afterBlock) return index
  if (!beforeBlock) return index - siblings.length
  return null
}

// Paths count element children only.
export function elementPath(
  el: Element,
  root: Element,
  blocks: Blocks = new Map()
): number[] | null {
  const path: number[] = []
  let current: Element = el

  while (current !== root) {
    const parent = current.parentElement
    if (!parent) return null
    const index = siblingIndex(current, Array.from(parent.children), blocks.get(parent))
    if (index === null) return null
    path.unshift(index)
    current = parent
  }

  return path
}

function textIndex(node: Text, blocks: Blocks): number | null {
  const parent = node.parentElement!
  const texts = Array.from(parent.childNodes).filter((child) => child.nodeType === Node.TEXT_NODE)
  return siblingIndex(node, texts, blocks.get(parent))
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
export function analyzeStatics(
  statics: string[],
  keys: (string | null | false)[] = []
): SlotDescriptor[] {
  if (statics.length <= 1) return []

  const template = document.createElement("template")
  template.innerHTML = statics
    .map((part, i) => {
      if (i === statics.length - 1) return part
      // A slot with a key, even "", is in a tag: an attribute, or attributes.
      return typeof keys[i] === "string" ? `${part} ${marker(i)}` : part + marker(i)
    })
    .join("")

  const root = template.content.firstElementChild
  const slots: SlotDescriptor[] = Array.from({ length: statics.length - 1 }, () => ({
    type: "unknown"
  }))
  if (!root) return slots

  const isBlock = (part: TextPart) => typeof part === "number" && keys[part] === false

  // First where the blocks are, as paths around them depend on it.
  const blocks: Blocks = new Map()
  const texts = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
  for (let node = texts.nextNode(); node; node = texts.nextNode()) {
    if (textParts((node as Text).data).some(isBlock)) {
      const parent = node.parentElement!
      blocks.set(parent, [...(blocks.get(parent) ?? []), node])
    }
  }

  const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT)

  for (let node: Node | null = root; node; node = walker.nextNode()) {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node as Text
      const parentPath = elementPath(text.parentElement!, root, blocks)
      const index = textIndex(text, blocks)
      if (!parentPath || index === null) continue

      // A text node can mix static text and several slots, such as
      // `Doubled: {{ n }} · {{ label }}`; each slot rewrites the whole node.
      // One holding a block is the block's: left to LiveView.
      const parts = textParts(text.data)
      if (parts.some(isBlock)) continue

      for (const part of parts) {
        if (typeof part === "number") {
          slots[part] = { type: "text", parentPath, textIndex: index, parts }
        }
      }
    } else {
      const el = node as Element
      const nodePath = elementPath(el, root, blocks)
      if (!nodePath) continue

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
      if (node) registry.set(i, { type: "text", node, parts: slot.parts })
    }
  })

  return registry
}

/** Applies a diff to registered nodes and returns how many changed. */
export function applyDiff(registry: Registry, diff: Diff): number {
  const values: SlotValues = (slot) => slotText(diff[String(slot)])
  let applied = 0

  for (const [slot, entry] of registry) {
    if (applyValue(entry, slot, values)) applied++
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

/**
 * Writes a slot's value to its node. A text node is rebuilt from all of its
 * parts, so every slot in it must have a value.
 */
export function applyValue(entry: RegistryEntry, slot: number, values: SlotValues): boolean {
  if (entry.type === "text") {
    const texts = entry.parts.map((part) => {
      if (typeof part === "string") return part
      const value = values(part)
      return value === null ? null : htmlText(value)
    })
    if (texts.includes(null)) return false

    const text = texts.join("")
    if (entry.node.nodeValue === text) return false
    entry.node.nodeValue = text
    return true
  }

  const value = values(slot)
  return value !== null && setAttribute(entry.node, entry.key, attributeValue(entry.key, value))
}

// A text slot renders escaped HTML; the DOM holds the text it stands for.
function htmlText(html: string): string {
  if (!html.includes("&")) return html

  const template = document.createElement("template")
  template.innerHTML = html
  return template.content.textContent ?? ""
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

// A negative index counts from the end, as `siblingIndex` gives it.
function at<T>(items: ArrayLike<T>, index: number): T | undefined {
  return items[index < 0 ? items.length + index : index]
}

export function walkPath(rootEl: Element, path: number[]): Element | null {
  let node: Element | undefined = rootEl
  for (const index of path) {
    node = at(node.children, index)
    if (!node) return null
  }
  return node
}

function getTextNodeAt(parent: Element, index: number): Text | null {
  const texts = Array.from(parent.childNodes).filter((child) => child.nodeType === Node.TEXT_NODE)
  return (at(texts, index) as Text | undefined) ?? null
}
