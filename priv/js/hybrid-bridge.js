/**
 * PhoenixVapor Hybrid Bridge
 *
 * LiveView hook for hybrid components. The server renders the component
 * inside a `phx-update="ignore"` wrapper whose `data-pv-props` attribute holds
 * the client props as JSON. LiveView keeps merging `data-*` attributes into an
 * ignored element, so `updated()` receives every props change.
 */

function readProps(el) {
  try {
    return JSON.parse(el.dataset.pvProps || "{}")
  } catch (e) {
    console.warn("[PhoenixVapor] Failed to parse data-pv-props:", e)
    return null
  }
}

export function createHybridHook(components) {
  return {
    mounted() {
      const name = this.el.dataset.pvClient
      const component = name && components[name]

      if (!component) {
        console.warn(`[PhoenixVapor] Component "${name}" not found in registry`)
        return
      }

      const bridge = {
        pushEvent: (event, params, callback) => this.pushEvent(event, params, callback),
        pushEventTo: (selector, event, params, callback) =>
          this.pushEventTo(selector, event, params, callback),
        handleEvent: (event, callback) => this.handleEvent(event, callback)
      }

      component.__applyProps(readProps(this.el) || {})
      component.__mount(this.el, bridge)
      this.__pvComponent = component
    },

    updated() {
      this.applyProps()
    },

    reconnected() {
      this.applyProps()
    },

    destroyed() {
      if (this.__pvComponent) this.__pvComponent.__unmount()
      this.__pvComponent = null
    },

    applyProps() {
      if (!this.__pvComponent) return
      const props = readProps(this.el)
      if (props) this.__pvComponent.__applyProps(props)
    }
  }
}

export function getHybridHooks(components) {
  return {
    PhoenixVaporHybrid: createHybridHook(components)
  }
}
