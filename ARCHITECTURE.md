# Architecture

PhoenixVapor compiles Vue template syntax into native LiveView rendered trees. Four progressive modes share a common foundation: Vue/Vapor templates and LiveView rendered diffs have the same statics/dynamics shape.

## Core: Statics/Dynamics Split

A Vue template compiles into a **split** — static HTML fragments and dynamic insertion points:

```
Template:  <div class="card"><h1>{{ title }}</h1><p>{{ body }}</p></div>
Statics:   ["<div class=\"card\"><h1>", "</h1><p>", "</p></div>"]
Dynamics:  [title, body]
```

This maps directly to `%Phoenix.LiveView.Rendered{}`:
- Statics sent once per fingerprint, cached by the client
- Only changed dynamics travel the wire on updates
- `v-if` → nested `%Rendered{}`
- `v-for` → `%Comprehension{}`

## Expression Evaluation

Template expressions are evaluated against LiveView assigns:

- Simple (`{{ count }}`, `item.name`) → Elixir map access via OXC AST
- Complex (`.filter()`, `.map()`, arrow functions) → QuickBEAM JS eval
- Change tracking: each slot knows which assigns it depends on (compile-time AST analysis)

## Mode 1: `~VUE` Sigil

Vue syntax as a template DSL. Zero client JS.

```
Template → Vize.vapor_split! → %Rendered{} → LiveView diff → morphdom
```

Expressions evaluate in Elixir. Events map to `phx-click`, `phx-submit`, etc. The browser runs the standard LiveView client — it doesn't know Vue exists.

## Mode 2: Reactive (`.vue` SFC)

Server-side Vue reactivity via QuickBEAM. Zero client JS.

```
SFC → ScriptSetup.parse → Runtime (GenServer + QuickBEAM)
    → Template → %Rendered{} with reactive state from JS runtime
```

A persistent QuickBEAM context per LiveView holds `ref()` values, `computed()` definitions, and function handlers. Vue's `@vue/reactivity` runs server-side on the BEAM. State survives across events but resets on process restart.

## Mode 3: Hybrid (`.vue` SFC)

Split reactivity — server owns data, client owns UI state.

```
SFC → Classifier (AST analysis)
    → Server: mount/render/handle_event (Elixir)
    → Client: Vue 3 component (JS, ~50KB)
    → Bridge: LiveView hook syncs props via data attributes
```

The compiler analyzes `<script setup>` and classifies each binding:

| Pattern | Classification |
|---------|---------------|
| `defineProps(["x"])` | Server prop |
| `ref(value)` | Client ref |
| `computed` using any prop | Mixed computed |
| Function with `"use server"` | Server action |
| Function writing to a prop | Server action (auto-detected) |
| Function writing only to refs | Client handler |

Server renders full HTML for first paint (SEO). Client hydrates with Vue 3 `createApp`, taking over reactive slots. Client interactions (search, sort, select) are instant — zero network. Server actions send events over the existing LiveView WebSocket.

### Wire Protocol

Initial render: server sends statics + dynamics + props JSON in `data-pv-props` attribute. Updates: only changed server slots + updated props JSON travel the wire. Client-only changes (typing in search) produce zero wire traffic.

### State Sync

- **Server → Client**: LiveView assign changes → re-render → diff with props JSON → hook's `updated()` → `__applyProps()` → Vue reactivity propagates
- **Client → Server**: `"use server"` function → `pushEvent` → `handle_event` → assign change → back to step 1
- **Client → Client**: `ref` mutation → computed recomputation → Vue re-render. No wire.

### Custom Elixir Code

A hybrid module is a standard LiveView. The `use PhoenixVapor.Hybrid` macro generates `render/1` and fallback `handle_event/3` stubs (via `@before_compile`) — everything else is yours to define. User-defined `handle_event` clauses take precedence over generated fallbacks.

The `"use server"` directive in the `.vue` file serves two purposes:
1. Tells the client codegen to generate a `pushEvent` call for that function name
2. Registers the event name so a fallback `handle_event` is generated if the developer doesn't write one

The developer writes the actual server logic in Elixir:

```elixir
def handle_event("deleteContact", %{"id" => id}, socket) do
  Repo.delete!(Contact, id)
  {:noreply, assign(socket, contacts: Repo.all(Contact))}
end
```

All standard LiveView callbacks work: `mount/3`, `handle_info/2`, `handle_params/3`, `terminate/2`. PubSub subscriptions, presence, streams — the full LiveView toolkit is available.

## Mode 4: Full Vue Runtime

Third-party Vue component libraries rendered server-side in QuickBEAM.

```
SFC + bundle → VueRuntime (GenServer + QuickBEAM + lexbor DOM)
             → HTML string → %Rendered{} → LiveView diff
```

Full Vue semantics: `provide`/`inject`, component composition, ARIA attributes. Used for libraries like Reka UI.

## Module Map

### Template / Render
- `PhoenixVapor` — main entry, `__using__` macro
- `PhoenixVapor.Sigil` — `~VUE` sigil
- `PhoenixVapor.Renderer` — Vapor IR → `%Rendered{}`
- `PhoenixVapor.Expr` — JS expression evaluation in Elixir
- `PhoenixVapor.Component` — component helpers
- `PhoenixVapor.Vue` — `.vue` file loading

### Reactive
- `PhoenixVapor.Reactive` — `use PhoenixVapor.Reactive, file: "X.vue"`
- `PhoenixVapor.Runtime` — QuickBEAM GenServer for reactive state
- `PhoenixVapor.ScriptSetup` — `<script setup>` parsing

### Hybrid
- `PhoenixVapor.Hybrid` — `use PhoenixVapor.Hybrid, file: "X.vue"`
- `PhoenixVapor.Hybrid.Classifier` — binding classification via AST
- `PhoenixVapor.Hybrid.ServerCodegen` — Elixir code generation
- `PhoenixVapor.Hybrid.ClientCodegen` — Vue 3 JS generation

### Full Runtime
- `PhoenixVapor.LiveVue` — `use PhoenixVapor.LiveVue, file: "X.vue", bundle: "..."`
- `PhoenixVapor.VueRuntime` — QuickBEAM GenServer for full Vue

### Client JS
- `priv/js/hybrid-bridge.js` — LiveView hook for hybrid mode
- `priv/js/vue-reactivity.js` — `@vue/reactivity` for server-side reactive mode
- `priv/js/runtime-setup.js` — QuickBEAM reactive runtime bootstrap
