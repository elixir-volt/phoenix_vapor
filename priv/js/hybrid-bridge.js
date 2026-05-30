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
      const expectedVersion = el.dataset.pvVersion

      if (expectedVersion && component.__pvVersion && component.__pvVersion !== expectedVersion) {
        window.location.reload()
        return
      }

      const initialProps = parseProps(el, "initial props")
      if (initialProps) component.__applyProps(initialProps)

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
      requestDeferred.call(this, initialProps, componentName)
    },

    updated() {
      if (!this.__pvComponent) return

      const props = parseProps(this.el, "props update")
      if (props) {
        this.__pvComponent.__applyProps(props)
        requestDeferred.call(this, props, this.el.dataset.pvClient)
      }
    },

    reconnected() {
      if (!this.__pvComponent) return

      const props = parseProps(this.el, "props on reconnect")
      if (props) this.__pvComponent.__applyProps(props)
    },

    destroyed() {
      this.__pvComponent = null
    }
  }
}

function requestDeferred(payload, componentName) {
  if (!payload || !payload.deferredProps) return

  for (const group of Object.keys(payload.deferredProps)) {
    this.pushEvent("pv:deferred", { component: componentName, group })
  }
}

function parseProps(el, label) {
  const propsAttr = el.dataset.pvProps
  if (!propsAttr) return null

  try {
    return JSON.parse(propsAttr)
  } catch (e) {
    console.warn(`[PhoenixVapor] Failed to parse ${label}:`, e)
    return null
  }
}

export function getHybridHooks(components) {
  return {
    PhoenixVaporHybrid: createHybridHook(components)
  }
}
