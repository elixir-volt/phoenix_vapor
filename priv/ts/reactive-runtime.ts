// Reactive runtime for PhoenixVapor.Runtime, evaluated in QuickBEAM.
//
// `__pv_setup(config)` builds refs, computeds and handlers from the component's
// `<script setup>`. The other globals read state and run handlers.

import { computed, ref, toRaw, type ComputedRef, type Ref } from "@vue/reactivity"

interface Config {
  refs?: Record<string, string>
  computeds?: Record<string, string>
  functions?: Record<string, string>
}

type State = Record<string, unknown>

declare global {
  var __pv_setup: (config: Config) => State
  var __pv_getState: () => State
  var __pv_setState: (updates: State) => State
  var __pv_callHandler: (name: string, params: unknown) => State
}

// A shallow copy, so handlers and callers never hold the reactive proxy.
function snapshot(value: unknown): unknown {
  const raw = toRaw(value)
  if (Array.isArray(raw)) return raw.slice()
  if (raw && typeof raw === "object") return { ...raw }
  return raw
}

globalThis.__pv_setup = (config) => {
  const refs: Record<string, Ref<unknown>> = {}
  const computedRefs: Record<string, ComputedRef<unknown>> = {}
  const handlers: Record<string, (params: unknown) => void> = {}

  for (const [name, init] of Object.entries(config.refs ?? {})) {
    refs[name] = ref(new Function(`return (${init})`)())
  }

  // Computeds are lazy and read their dependencies through a scope, so a
  // computed may use one declared after it and only tracks the names its
  // expression actually reads.
  const scope = new Proxy(
    {},
    {
      has: (_, key) => typeof key === "string" && (key in refs || key in computedRefs),
      get: (_, key) =>
        typeof key === "string" ? (refs[key] ?? computedRefs[key])?.value : undefined
    }
  )

  for (const [name, expr] of Object.entries(config.computeds ?? {})) {
    const source = expr.trim()
    // `computed(() => { ... })` arrives as its block body.
    const body = source.startsWith("{") ? source : `return (${source})`
    const getter = new Function("__scope", `with (__scope) { ${body} }`)
    computedRefs[name] = computed(() => getter(scope))
  }

  // Handler bodies use bare ref names (`count++`, `items.push(...)`). They run
  // against copies passed as parameters, and the results are written back.
  const refNames = Object.keys(refs)

  for (const [name, body] of Object.entries(config.functions ?? {})) {
    const fn = new Function("__params", ...refNames, `${body}\nreturn { ${refNames.join(", ")} }`)

    handlers[name] = (params) => {
      const result = fn(params, ...refNames.map((n) => snapshot(refs[n]!.value)))
      for (const n of refNames) refs[n]!.value = result[n]
    }
  }

  globalThis.__pv_getState = () => {
    const state: State = {}
    for (const [key, r] of Object.entries(refs)) state[key] = snapshot(r.value)
    for (const [key, c] of Object.entries(computedRefs)) state[key] = snapshot(c.value)
    return state
  }

  globalThis.__pv_setState = (updates) => {
    for (const [key, value] of Object.entries(updates)) {
      if (refs[key]) refs[key].value = value
    }
    return globalThis.__pv_getState()
  }

  globalThis.__pv_callHandler = (name, params) => {
    handlers[name]?.(params)
    return globalThis.__pv_getState()
  }

  return globalThis.__pv_getState()
}
