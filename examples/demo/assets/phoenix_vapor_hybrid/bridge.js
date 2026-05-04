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

import { createVaporApp, shallowReactive } from 'vue'

export function createHybridHook(components) {
  return {
    mounted() {
      const el = this.el
      const componentName = el.dataset.pvClient

      if (!componentName || !components[componentName]) {
        console.warn(`[PhoenixVapor] Component "${componentName}" not found in registry`)
        return
      }

      const mod = components[componentName]
      const component = mod.default || mod

      if (!component) {
        console.warn(`[PhoenixVapor] No component found for "${componentName}"`)
        return
      }

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

      this.__pvProps = shallowReactive({ ...initialProps })
      if (mod.__applyProps) mod.__applyProps(this.__pvProps)

      const app = createVaporApp(component, this.__pvProps)
      app.config.warnHandler = (msg) => {
        if (!msg.includes('Extraneous')) console.warn('[Vue]', msg)
      }
      el.innerHTML = ''
      const instance = app.mount(el)
      this.__pvInstance = instance

      this.__pvApp = app
      this.__pvModule = mod
    },

    updated() {
      if (!this.__pvModule || !this.__pvProps) return

      const propsAttr = this.el.dataset.pvProps
      if (!propsAttr) return

      try {
        const newProps = JSON.parse(propsAttr)
        Object.assign(this.__pvProps, newProps)
        this.__pvModule.__applyProps(this.__pvProps)
      } catch (e) {
        console.warn("[PhoenixVapor] Failed to parse props update:", e)
      }
    },

    reconnected() {
      if (!this.__pvModule || !this.__pvProps) return

      const propsAttr = this.el.dataset.pvProps
      if (!propsAttr) return

      try {
        const newProps = JSON.parse(propsAttr)
        Object.assign(this.__pvProps, newProps)
        this.__pvModule.__applyProps(this.__pvProps)
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
      this.__pvProps = null
    }
  }
}

export function getHybridHooks(components) {
  return {
    PhoenixVaporHybrid: createHybridHook(components)
  }
}
