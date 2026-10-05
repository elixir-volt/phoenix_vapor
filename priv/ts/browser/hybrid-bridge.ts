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
  /** Reports `refs` while a session replayer records; see `reportRefs`. */
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
  stopReporting?: () => void
}

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

// A component's refs as plain data, by name.
function snapshot(refs: Refs): Record<string, unknown> {
  const values: Record<string, unknown> = {}

  for (const [name, ref] of Object.entries(refs)) {
    const value = plain(ref.value, new Set())
    if (value !== undefined) values[name] = value
  }

  return values
}

// A session replayer, such as PhoenixReplay, records state that lives only in
// the browser through window events, so PhoenixVapor needs no dependency on
// it: `phx_replay:start` and `phx_replay:stop` say when a session is recorded,
// with `{state: null}` when client state isn't, and `phx_replay:state`
// reports `{key, changes}`, a shallow delta merged into what's recorded under
// `key`. Recording may start before or after a component mounts.
const START_EVENT = "phx_replay:start"
const STOP_EVENT = "phx_replay:stop"
const STATE_EVENT = "phx_replay:state"

type Reporter = { start(): void; stop(): void }

let recording = false
const reporters = new Set<Reporter>()

if (typeof window !== "undefined") {
  window.addEventListener(START_EVENT, (event) => {
    const detail = (event as CustomEvent<{ state?: unknown } | null>).detail
    if (detail?.state == null) return

    recording = true
    for (const reporter of reporters) reporter.start()
  })

  window.addEventListener(STOP_EVENT, () => {
    recording = false
    for (const reporter of reporters) reporter.stop()
  })
}

/**
 * Reports a component's refs under `key` while a session is recorded: all of
 * them when recording starts, or when the component mounts during one, then
 * only the refs that changed.
 */
function reportRefs(hook: HookContext, key: string): (refs: Refs, watch: Watch) => void {
  const report = (changes: Record<string, unknown>) => {
    if (Object.keys(changes).length > 0)
      window.dispatchEvent(new CustomEvent(STATE_EVENT, { detail: { key, changes } }))
  }

  return (refs, watch) => {
    let stopWatching: (() => void) | undefined
    let last: Record<string, string> = {}

    const reporter: Reporter = {
      start() {
        stopWatching?.()
        const values = snapshot(refs)
        last = Object.fromEntries(Object.entries(values).map(([n, v]) => [n, JSON.stringify(v)]))
        report(values)

        stopWatching = watch(
          () => snapshot(refs),
          (next) => {
            const changes: Record<string, unknown> = {}

            for (const [name, value] of Object.entries(next as Record<string, unknown>)) {
              const json = JSON.stringify(value)
              if (last[name] !== json) changes[name] = value
              last[name] = json
            }

            report(changes)
          },
          { deep: true, immediate: false }
        )
      },
      stop() {
        stopWatching?.()
        stopWatching = undefined
      }
    }

    reporters.add(reporter)
    if (recording) reporter.start()

    hook.stopReporting = () => {
      reporter.stop()
      reporters.delete(reporter)
    }
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
        // Stable across reconnects; the server replays under the same key.
        record: reportRefs(this, `phoenix_vapor:${this.el.id}`)
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
      this.stopReporting?.()
      this.instance?.unmount()
      this.instance = undefined
    }
  }
}

export function getHybridHooks(components: Record<string, HybridComponent>) {
  return { PhoenixVaporHybrid: createHybridHook(components) }
}
