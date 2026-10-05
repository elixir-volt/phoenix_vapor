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
  record?(sources: Sources, watch: Watch, unref: Unref): void
}

/**
 * The client state a session replay needs, by name, as `<script setup>`
 * declares it: refs, composables' results, `reactive()` objects.
 */
export type Sources = Record<string, unknown>

/** Vue's `unref`, which unwraps a ref and leaves anything else as it is. */
export type Unref = (source: unknown) => unknown

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

// A ref's value as plain data; a value that isn't, or `undefined`, is
// `null`, so the replay doesn't keep showing an earlier value.
const plainValue = (value: unknown): unknown => plain(value, new Set()) ?? null

// A session replayer, such as PhoenixReplay, records state that lives only in
// the browser through window events, so PhoenixVapor needs no dependency on
// it: `phx_replay:start` and `phx_replay:stop` say when a session is recorded,
// with `{state: null}` when client state isn't, and `phx_replay:state`
// reports `{key, changes}`, a shallow delta merged into what's recorded under
// `key`. While recording, `<html>` carries `data-phx-replay` with the start's
// detail as JSON, for code that loads or mounts after the start.
const START_EVENT = "phx_replay:start"
const STOP_EVENT = "phx_replay:stop"
const STATE_EVENT = "phx_replay:state"

type Settings = { flush?: number }
type Reporter = { start(settings: Settings): void; stop(): void; flush(): void }

const reporters = new Set<Reporter>()

// The client-state settings while they're recorded, from the attribute on
// `<html>`, or null.
function recordingState(): Settings | null {
  const recording = document.documentElement.dataset.phxReplay
  if (!recording) return null

  try {
    return (JSON.parse(recording) as { state?: Settings | null }).state ?? null
  } catch {
    return null
  }
}

if (typeof window !== "undefined") {
  window.addEventListener(START_EVENT, (event) => {
    const settings = (event as CustomEvent<{ state?: Settings | null } | null>).detail?.state
    if (settings == null) return
    for (const reporter of reporters) reporter.start(settings)
  })

  window.addEventListener(STOP_EVENT, () => {
    for (const reporter of reporters) reporter.stop()
  })

  // Changes waiting for the next flush go out before the replayer sends its
  // last batch: when the page is hidden, and when it navigates away, which
  // stops a recording. Capturing runs these before the replayer's handlers.
  const flushAll = () => {
    for (const reporter of reporters) reporter.flush()
  }

  document.addEventListener(
    "visibilitychange",
    () => {
      if (document.hidden) flushAll()
    },
    { capture: true }
  )

  window.addEventListener("phx:page-loading-start", flushAll, { capture: true })
}

/**
 * Reports a component's client state under `key` while it's recorded: all
 * of it when recording starts, or when the component mounts during one, then
 * the latest value of each source that changed, at most once per the
 * replayer's flush interval, so state that changes at frame rate, such as a
 * pointer position, costs one report per flush.
 */
function reportRefs(
  hook: HookContext,
  key: string
): (sources: Sources, watch: Watch, unref: Unref) => void {
  const report = (changes: Record<string, unknown>) =>
    window.dispatchEvent(new CustomEvent(STATE_EVENT, { detail: { key, changes } }))

  return (sources, watch, unref) => {
    let stops: Array<() => void> = []
    let pending: Record<string, unknown> = {}
    let timer: ReturnType<typeof setTimeout> | undefined

    const flush = () => {
      timer = undefined
      const changes = pending
      pending = {}
      if (Object.keys(changes).length > 0) report(changes)
    }

    const reporter: Reporter = {
      start(settings) {
        reporter.stop()

        const values: Record<string, unknown> = {}
        const last: Record<string, string> = {}

        for (const [name, source] of Object.entries(sources)) {
          // A function, such as useClipboard's copy, is behaviour, not
          // state; unref leaves it uncalled.
          if (typeof unref(source) === "function") continue

          values[name] = plainValue(unref(source))
          last[name] = JSON.stringify(values[name])

          const changed = () => {
            const value = plainValue(unref(source))
            const json = JSON.stringify(value)
            if (json === last[name]) return

            last[name] = json
            pending[name] = value
            timer ??= setTimeout(flush, settings.flush ?? 0)
          }

          stops.push(watch(() => unref(source), changed, { deep: true, immediate: false }))
        }

        report(values)
      },
      stop() {
        for (const stop of stops) stop()
        stops = []
        clearTimeout(timer)
        timer = undefined
        pending = {}
      },
      flush() {
        clearTimeout(timer)
        flush()
      }
    }

    reporters.add(reporter)
    const settings = recordingState()
    if (settings) reporter.start(settings)

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
