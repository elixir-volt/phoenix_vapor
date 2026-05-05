/**
 * PhoenixVapor Hybrid Bridge
 *
 * Connects LiveView's diff protocol to the Vue Vapor reactive system.
 * Registers a LiveView hook that:
 * - On mount: creates a Vue Vapor app, feeds initial props from data-pv-props
 * - On update: parses new props from the diff, feeds them to __applyProps
 * - On reconnect: re-syncs full props from the server
 * - Provides pushEvent for server actions
 */

export function createHybridHook(components) {
  return {
    mounted() {
      console.error('[PV-BRIDGE] mounted() fired!')
      const el = this.el
      const componentName = el.dataset.pvClient

      if (!componentName || !components[componentName]) {
        console.warn(`[PhoenixVapor] Component "${componentName}" not found in registry`)
        return
      }

      const mod = components[componentName]

      const bridge = {
        pushEvent: (event, params, callback) => {
          this.pushEvent(event, params, callback)
        },
        handleEvent: (event, callback) => {
          this.handleEvent(event, callback)
        }
      }

      if (mod.__setBridge) mod.__setBridge(bridge)

      const initialProps = JSON.parse(el.dataset.pvProps || '{}')
      if (mod.__applyProps) mod.__applyProps(initialProps)

      if (mod.__mount) {
        el.innerHTML = ''
        mod.__mount(el, bridge)
      }

      this.__pvModule = mod
    },

    updated() {
      if (!this.__pvModule) return

      const propsAttr = this.el.dataset.pvProps
      if (!propsAttr) return

      try {
        const newProps = JSON.parse(propsAttr)
        this.__pvModule.__applyProps(newProps)
      } catch (e) {
        console.warn("[PhoenixVapor] Failed to parse props update:", e)
      }
    },

    reconnected() {
      if (!this.__pvModule) return

      const propsAttr = this.el.dataset.pvProps
      if (!propsAttr) return

      try {
        const newProps = JSON.parse(propsAttr)
        this.__pvModule.__applyProps(newProps)
      } catch (e) {
        console.warn("[PhoenixVapor] Failed to parse props on reconnect:", e)
      }
    },

    destroyed() {
      if (this.__pvApp) {
        this.__pvApp.unmount()
      }
      this.__pvApp = null
      this.__pvModule = null
    }
  }
}

export function getHybridHooks(components) {
  return {
    PhoenixVaporHybrid: createHybridHook(components)
  }
}
