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
}

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
        handleEvent: (event, callback) => this.handleEvent(event, callback)
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
      this.instance?.unmount()
      this.instance = undefined
    }
  }
}

export function getHybridHooks(components: Record<string, HybridComponent>) {
  return { PhoenixVaporHybrid: createHybridHook(components) }
}
