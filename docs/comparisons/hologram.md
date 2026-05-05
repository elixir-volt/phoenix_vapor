# PhoenixVapor vs Hologram: Deep Comparison

Two Elixir projects that let you build interactive UIs without writing JavaScript directly, but with fundamentally different philosophies and architectures.

---

## Core Philosophy

**Hologram**: Write everything in Elixir. The framework compiles Elixir code to JavaScript for the client. No frontend language — Elixir runs on both sides.

**PhoenixVapor**: Write templates in Vue syntax. The compiler generates both Elixir server code and Vue/JS client code from a single `.vue` file. The frontend runs real Vue.

| | Hologram | PhoenixVapor (Hybrid) |
|---|---|---|
| **Source language** | Elixir everywhere | Vue SFC (HTML + JS + CSS) |
| **Client runtime** | Custom Elixir→JS interpreter | Standard Vue 3 |
| **Template syntax** | Custom HOLO (`{@var}`, `{%for}`) | Standard Vue (`{{ var }}`, `v-for`) |
| **Component model** | Custom (Hologram.Component) | Standard Vue components |
| **Builds on** | Phoenix (replacement layer) | Phoenix LiveView (extension) |
| **JS frameworks used** | None — custom VDOM | Vue 3 (proven, ecosystem) |

---

## Architecture

### Hologram

```
Elixir Code
     │
     ▼
Compiler (Elixir AST → IR → JavaScript)
     │
     ├── Client JS: Elixir interpreter + VDOM + event system
     └── Server: HTTP/2 command handler
```

Hologram compiles Elixir modules to JavaScript. The client runs an Elixir interpreter in JS that evaluates your action code. State lives in the browser. Server communication happens via HTTP/2 for "commands" (DB access, etc.).

### PhoenixVapor Hybrid

```
Vue SFC
     │
     ▼
Classifier (OXC AST analysis)
     │
     ├── Server: Elixir LiveView (mount, render, handle_event)
     └── Client: Vue 3 component (createApp, reactive props)
     └── Bridge: LiveView hook syncs props via WebSocket
```

PhoenixVapor compiles Vue SFCs using Vize (Rust NIF). Server-owned data flows via LiveView diffs. Client-owned state is standard Vue reactivity. The bridge syncs them over the existing LiveView WebSocket.

---

## State Model

### Hologram

State lives **in the browser**. The client is the source of truth for UI state. Server commands are async RPC calls.

```elixir
# Action (runs in browser as compiled JS)
def action(:increment, params, component) do
  put_state(component, :count, component.state.count + params.step)
end

# Command (runs on server)
def command(:save, params, server) do
  Repo.insert(%Counter{value: params.count})
  put_action(server, :saved)
end
```

- Actions: client-side, instant, update browser state
- Commands: server-side, async, for DB/auth/privileged ops
- The developer explicitly chooses action vs command

### PhoenixVapor Hybrid

State is **split by ownership**. Server-owned data (from DB) lives in LiveView assigns. Client-owned state (search, sort, dialogs) lives in Vue refs.

```vue
<script setup>
defineProps(["contacts"])          // server-owned
const search = ref("")             // client-owned
const filtered = computed(...)     // mixed derivation

function deleteContact(id) {       // server action
  "use server"
}
</script>
```

- `defineProps` → server (LiveView assigns)
- `ref()` → client (Vue reactivity, instant)
- `"use server"` → server action (auto-detected)
- The compiler classifies automatically via AST analysis

### Key Difference

Hologram requires the developer to decide action vs command for every operation. PhoenixVapor auto-classifies based on what the code accesses — if a function writes to a prop (server data), it's a server action; if it only touches client refs, it's a client handler.

---

## Compilation

### Hologram

Compiles **Elixir code to JavaScript**. This is the hard part — it needs to implement enough of Elixir's semantics in JS to run pattern matching, pipe operators, Enum functions, etc.

```
Elixir AST → Hologram IR → JavaScript
```

The client includes an Elixir interpreter/runtime in JS that can evaluate compiled Elixir expressions. This means:
- Pattern matching works in the browser
- Enum/Map/String functions available client-side
- Elixir data types (tuples, atoms, keyword lists) represented in JS

The compiler handles: function definitions, pattern matching, guards, pipe operators, comprehensions, structs, protocols (partial).

### PhoenixVapor

Compiles **Vue SFCs to both Elixir and JS**. Uses existing mature toolchains:

```
Vue SFC → Vize (Rust) → Standard Vue 3 render function (JS)
       → OXC (Rust) → AST analysis → Elixir codegen
       → QuickBEAM → server-side computed evaluation
```

No language translation needed — Vue/JS stays as JS, Elixir stays as Elixir. The compiler only needs to:
- Classify bindings (which are server vs client)
- Generate Elixir `mount`/`render`/`handle_event`
- Post-process the Vize output for bridge wiring

### Key Difference

Hologram solves a harder problem (Elixir→JS compilation) but limits what Elixir features work client-side. PhoenixVapor sidesteps the problem entirely — JS runs as JS, Elixir runs as Elixir, a thin bridge connects them.

---

## Template System

### Hologram

Custom `~HOLO` sigil with Elixir-flavored syntax:

```elixir
~HOLO"""
<div>
  <h1>{@title}</h1>
  {%for item <- @items}
    <p>{item.name}</p>
  {/for}
  {%if @show?}
    <span>Visible</span>
  {/if}
</div>
"""
```

### PhoenixVapor

Standard Vue template syntax:

```vue
<template>
  <div>
    <h1>{{ title }}</h1>
    <p v-for="item in items" :key="item.id">{{ item.name }}</p>
    <span v-if="show">Visible</span>
  </div>
</template>
```

### Key Difference

Hologram's syntax is unique — developers learn a new template language. PhoenixVapor uses standard Vue syntax — millions of developers already know it, and all Vue tooling (IDE support, linting, formatting) works out of the box.

---

## Client Runtime

### Hologram

Custom runtime (~unknown size, includes):
- Elixir interpreter in JS
- Virtual DOM implementation
- Component lifecycle
- Event system
- HTTP/2 transport
- Serializer/deserializer for Elixir terms

### PhoenixVapor

Standard Vue 3 runtime (~50KB gzip):
- Proven virtual DOM (or Vapor mode for direct DOM)
- Full reactive system (`ref`, `computed`, `watch`)
- Component lifecycle
- Standard event system
- Ecosystem: Vue devtools, composables, component libraries (Reka UI, etc.)

### Key Difference

Hologram ships a custom runtime. PhoenixVapor ships standard Vue — any Vue component library, composable, or tool works immediately.

---

## Server Communication

### Hologram

HTTP/2 persistent connections. Commands are async RPC:

```
Client: dispatch command → HTTP/2 POST → Server
Server: execute command → HTTP/2 response → Client
Client: execute resulting action → update state → re-render
```

No WebSocket. No persistent server process per user. Stateless server — commands are pure request/response.

### PhoenixVapor

LiveView WebSocket (existing Phoenix infrastructure):

```
Client: pushEvent → WebSocket → Server
Server: handle_event → assign → re-render → diff → WebSocket → Client
Client: bridge receives diff → update Vue props → Vue re-renders
```

Persistent server process per user (LiveView). Full LiveView features: PubSub, presence, streams.

### Key Difference

Hologram is stateless server-side — lower memory, no process per user, but no real-time push. PhoenixVapor inherits LiveView's stateful model — higher memory but real-time server push, PubSub integration, collaborative features.

---

## Developer Experience

### Hologram

One language everywhere:
```elixir
defmodule Counter do
  use Hologram.Component

  def init(_props, component, _server) do
    put_state(component, :count, 0)
  end

  def template do
    ~HOLO"""
    <p>{@count}</p>
    <button $click={:increment, step: 1}>+</button>
    """
  end

  def action(:increment, params, component) do
    put_state(component, :count, component.state.count + params.step)
  end
end
```

### PhoenixVapor Hybrid

One file, two languages auto-split:
```vue
<script setup>
import { ref, computed } from "vue"
const props = defineProps(["items"])
const search = ref("")
const filtered = computed(() => props.items.filter(...))

function deleteItem(id) {
  "use server"
  props.items = props.items.filter(i => i.id !== id)
}
</script>

<template>
  <input v-model="search" />
  <div v-for="item in filtered">{{ item.name }}</div>
</template>
```

```elixir
defmodule MyApp.ItemsLive do
  use PhoenixVapor, file: "Items.vue"

  def mount(_, _, socket), do: {:ok, assign(socket, items: Repo.all(Item))}

  def handle_event("deleteItem", %{"id" => id}, socket) do
    Repo.delete!(Item, id)
    {:noreply, assign(socket, items: Repo.all(Item))}
  end
end
```

---

## Ecosystem & Maturity

| | Hologram | PhoenixVapor |
|---|---|---|
| **First release** | 2022 | 2025 |
| **Downloads (all time)** | ~3,200 | New |
| **JS framework deps** | None (custom) | Vue 3 (stable, massive ecosystem) |
| **Component libraries** | Build your own | Any Vue library (Reka UI, PrimeVue, etc.) |
| **IDE support** | Limited (custom syntax) | Full Vue tooling (Volar, ESLint, etc.) |
| **Learning curve** | Learn HOLO syntax + action/command model | Know Vue? You're done. |
| **Phoenix integration** | Runs on top, replaces LiveView | Extends LiveView |
| **SSR** | Built-in (server renders first page) | Built-in (server renders all HTML) |

---

## What Each Does Better

### Hologram wins at

- **Single language**: No context-switching between Elixir and JS
- **Server statelessness**: No process per user, lower memory
- **Pattern matching in UI**: Elixir's pattern matching works in action handlers
- **No JS bundle management**: No npm, no node_modules, no bundler config
- **Explicit control**: Developer decides exactly what runs where

### PhoenixVapor wins at

- **Standard tooling**: Vue DevTools, ESLint, Prettier, Volar all work
- **Component ecosystem**: Any Vue component library works immediately
- **Proven runtime**: Vue 3 is battle-tested at massive scale
- **Auto-classification**: Compiler determines server vs client automatically
- **LiveView integration**: PubSub, presence, streams, collaborative features
- **Bundle size predictability**: Vue 3 is a known quantity (~50KB)
- **Familiar syntax**: Vue templates are known by millions of developers
- **CSS ecosystem**: Scoped styles, CSS modules, Tailwind — all standard

---

## Summary

**Hologram** bets that Elixir developers shouldn't need to learn JavaScript at all. It solves this by compiling Elixir to JS and running a custom client runtime. The tradeoff: you lose access to the JS ecosystem and must wait for Hologram to implement each Elixir feature client-side.

**PhoenixVapor** bets that Vue's template syntax and reactivity model are the best way to build UIs, and that Elixir/LiveView is the best way to manage server state. It solves this by compiling Vue SFCs into both sides from a single file. The tradeoff: you write some JavaScript (in Vue syntax), but you get the entire Vue ecosystem for free.

Both eliminate "write a JSON API + build a SPA" drudgery. Both give you server-rendered first paint. Both let you build interactive UIs primarily in Elixir. They just disagree on whether the client should run Elixir-compiled-to-JS or real JS with a Vue framework.
