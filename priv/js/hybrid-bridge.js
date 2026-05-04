/**
 * PhoenixVapor Hybrid Bridge
 *
 * Connects LiveView's diff protocol to the Vue Vapor reactive system.
 * Registers a LiveView hook that:
 * - On mount: reads initial props from data-pv-props, initializes the component
 * - On update: parses new props from the diff, feeds them to __applyProps
 * - On reconnect: re-syncs full props from the server
 * - Provides pushEvent for server actions
 */

export function createHybridHook(components) {
  return {
    mounted() {
      const el = this.el
      const componentName = el.dataset.pvClient

      if (!componentName || !components[componentName]) {
        console.warn(`[PhoenixVapor] Component "${componentName}" not found in registry`)
        return
      }

      const component = components[componentName]

      const bridge = {
        pushEvent: (event, params, callback) => {
          this.pushEvent(event, params, callback)
        },
        pushEventTo: (selector, event, params, callback) => {
          this.pushEventTo(selector, event, params, callback)
        },
        handleEvent: (event, callback) => {
          this.handleEvent(event, callback)
        }
      }

      component.__mount(el, bridge)
      this.__pvComponent = component
    },

    updated() {
      if (!this.__pvComponent) return

      const propsAttr = this.el.dataset.pvProps
      if (!propsAttr) return

      try {
        const props = JSON.parse(propsAttr)
        this.__pvComponent.__applyProps(props)
      } catch (e) {
        console.warn("[PhoenixVapor] Failed to parse props update:", e)
      }
    },

    reconnected() {
      if (!this.__pvComponent) return

      const propsAttr = this.el.dataset.pvProps
      if (!propsAttr) return

      try {
        const props = JSON.parse(propsAttr)
        this.__pvComponent.__applyProps(props)
      } catch (e) {
        console.warn("[PhoenixVapor] Failed to parse props on reconnect:", e)
      }
    },

    destroyed() {
      this.__pvComponent = null
    }
  }
}

export function getHybridHooks(components) {
  return {
    PhoenixVaporHybrid: createHybridHook(components)
  }
}
