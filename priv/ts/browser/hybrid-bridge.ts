// LiveView hook for hybrid components.
//
// The server renders a hybrid component inside a `phx-update="ignore"` wrapper
// whose `data-pv-props` attribute holds the client props as JSON. LiveView
// keeps merging `data-*` attributes into an ignored element, so `updated()`
// receives every props change.

export type Props = Record<string, unknown>

export interface Bridge {
  pushEvent(event: string, payload: object, callback?: (reply: unknown) => void): void
  pushEventTo(
    selector: string,
    event: string,
    payload: object,
    callback?: (reply: unknown) => void
  ): void
  handleEvent(event: string, callback: (payload: unknown) => void): void
  /** Reports `refs` while the session is recorded; see `recordRefs`. */
  record?(refs: Refs, watch: Watch): void
}

/** A component's refs by name, as `<script setup>` declares them. */
export type Refs = Record<string, { value: unknown }>

/** Vue's `watch`, which the generated module passes in. */
export type Watch = (
  source: () => unknown,
  callback: (value: unknown) => void,
  options: { deep: boolean; immediate: boolean }
) => () => void

// A mounted hybrid component.
export interface HybridInstance {
  applyProps(props: Props): void
  unmount(): void
}

// The module PhoenixVapor generates for each hybrid component.
export interface HybridComponent {
  __mount(el: HTMLElement, bridge: Bridge, props: Props): HybridInstance
}

// The parts of a LiveView hook instance the bridge uses.
interface HookContext extends Bridge {
  el: HTMLElement
  instance?: HybridInstance
  stopRecording?: () => void
}

// How long the refs must stay unchanged before they're reported.
const REPORT_DELAY = 250

// A value as plain data: strings, numbers, booleans, null, arrays and plain
// objects. Anything else, such as a template ref's element or a component
// instance, or a cycle, is left out.
function plain(value: unknown, seen: Set<object>): unknown {
  if (value === null || ["string", "number", "boolean"].includes(typeof value)) return value
  if (typeof value !== "object" || seen.has(value)) return undefined

  const proto = Object.getPrototypeOf(value) as unknown
  if (!Array.isArray(value) && proto !== Object.prototype && proto !== null) return undefined

  seen.add(value)
  const result = Array.isArray(value)
    ? value.map((item) => plain(item, seen) ?? null)
    : Object.fromEntries(
        Object.entries(value)
          .map(([key, item]) => [key, plain(item, seen)] as const)
          .filter(([, item]) => item !== undefined)
      )
  seen.delete(value)
  return result
}

// A component's refs as plain data, for the `__pv_refs` event.
function snapshot(refs: Refs): object {
  const values: Record<string, unknown> = {}

  for (const [name, ref] of Object.entries(refs)) {
    const value = plain(ref.value, new Set())
    if (value !== undefined) values[name] = value
  }

  return values
}

/**
 * While the server says the session is being recorded, with `pv:record`,
 * reports the registered refs as `__pv_refs`, debounced, so the recording
 * has the client's state. Until then a registration is only kept.
 */
function recordRefs(hook: HookContext): (refs: Refs, watch: Watch) => void {
  let recording = false
  const waiting: Array<() => void> = []
  const stops: Array<() => void> = []

  const start = (refs: Refs, watch: Watch) => {
    let timer: ReturnType<typeof setTimeout> | undefined
    const report = () => hook.pushEvent("__pv_refs", snapshot(refs))
    const changed = () => {
      clearTimeout(timer)
      timer = setTimeout(report, REPORT_DELAY)
    }

    // Their initial values are the server's too, so only changes are reported.
    stops.push(watch(() => snapshot(refs), changed, { deep: true, immediate: false }))
    stops.push(() => clearTimeout(timer))
  }

  hook.handleEvent("pv:record", () => {
    recording = true
    for (const begin of waiting.splice(0)) begin()
  })

  hook.stopRecording = () => {
    for (const stop of stops.splice(0)) stop()
  }

  return (refs, watch) => {
    if (recording) start(refs, watch)
    else waiting.push(() => start(refs, watch))
  }
}

function readProps(el: HTMLElement): Props | null {
  try {
    return JSON.parse(el.dataset.pvProps ?? "{}") as Props
  } catch (error) {
    console.warn("[PhoenixVapor] Failed to parse data-pv-props:", error)
    return null
  }
}

function applyProps(hook: HookContext) {
  const props = hook.instance && readProps(hook.el)
  if (props) hook.instance!.applyProps(props)
}

export function createHybridHook(components: Record<string, HybridComponent>) {
  return {
    mounted(this: HookContext) {
      const name = this.el.dataset.pvClient
      const component = name ? components[name] : undefined

      if (!component) {
        console.warn(`[PhoenixVapor] Component "${name}" not found in registry`)
        return
      }

      const bridge: Bridge = {
        pushEvent: (event, payload, callback) => this.pushEvent(event, payload, callback),
        pushEventTo: (selector, event, payload, callback) =>
          this.pushEventTo(selector, event, payload, callback),
        handleEvent: (event, callback) => this.handleEvent(event, callback),
        record: recordRefs(this)
      }

      this.instance = component.__mount(this.el, bridge, readProps(this.el) ?? {})
    },

    updated(this: HookContext) {
      applyProps(this)
    },

    reconnected(this: HookContext) {
      applyProps(this)
    },

    destroyed(this: HookContext) {
      this.stopRecording?.()
      this.instance?.unmount()
      this.instance = undefined
    }
  }
}

export function getHybridHooks(components: Record<string, HybridComponent>) {
  return { PhoenixVaporHybrid: createHybridHook(components) }
}
