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
- Change tracking: on each render, a slot is re-evaluated only when an assign its expression reads is in `__changed__`

## Mode 1: `~VUE` Sigil

Vue syntax as a template DSL. Zero client JS.

```
Template → Vize.vapor_split! → %Rendered{} → LiveView diff → morphdom
```

Expressions evaluate in Elixir. Events map to `phx-click`, `phx-submit`, etc. The browser runs the standard LiveView client — it doesn't know Vue exists.

## Mode 2: Reactive (`.vue` SFC)

Server-side Vue reactivity via QuickBEAM. Zero client JS.

```
SFC → Compiler.ScriptSetup.parse → Reactive.Runtime (GenServer + QuickBEAM)
    → Template → %Rendered{} with reactive state from JS runtime
```

A persistent QuickBEAM context per LiveView holds `ref()` values, `computed()` definitions, and function handlers. Vue's `@vue/reactivity` runs server-side on the BEAM. State survives across events but resets on process restart.

## Mode 3: Hybrid (`.vue` SFC)

Split reactivity — server owns data, client owns UI state.

```
SFC → Classifier (AST analysis)
    → Server: render/1 and fallback handle_event/3 (Elixir); mount/3 is yours
    → Client: Vue 3 component module (<Name>.hybrid.js)
    → Bridge: LiveView hook syncs props via data-pv-props
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

Server renders full HTML for first paint (SEO). The hook then mounts the Vue component with `createApp` in place of that HTML; the wrapper is `phx-update="ignore"`, so later server renders don't touch the DOM Vue owns. Client interactions (search, sort, select) are instant — zero network. Server actions send events over the existing LiveView WebSocket.

### Wire Protocol

Initial render: server sends statics + dynamics, with the props JSON as the wrapper's `data-pv-props` dynamic. Updates: the props JSON travels only when a client prop changed. Client-only changes (typing in search) produce zero wire traffic.

### State Sync

- **Server → Client**: LiveView assign changes → re-render → diff with props JSON → hook's `updated()` → the instance's `applyProps()` → Vue reactivity propagates
- **Client → Server**: `"use server"` function → `pushEvent` → `handle_event` → assign change → back to step 1
- **Client → Client**: `ref` mutation → computed recomputation → Vue re-render. No wire.

### Custom Elixir Code

A hybrid module is a standard LiveView. The `use PhoenixVapor` macro generates `render/1` and fallback `handle_event/3` stubs (via `@before_compile`) — everything else is yours to define. User-defined `handle_event` clauses take precedence over generated fallbacks.

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
SFC + bundle → Full.Runtime (GenServer + QuickBEAM + lexbor DOM)
             → HTML string → %Rendered{} → LiveView diff
```

Full Vue semantics: `provide`/`inject`, component composition, ARIA attributes. Used for libraries like Reka UI.

## Module Map

### Public
- `PhoenixVapor` — `use PhoenixVapor`, which picks the mode from the `.vue` file, and `render/2`
- `PhoenixVapor.Sigil` — `~VUE` sigil
- `PhoenixVapor.Component` — the `vue/1` helper for function components
- `PhoenixVapor.Vue` — `.vue` files as function components
- `PhoenixVapor.Template` — a compiled template
- `PhoenixVapor.ExpressionError` — an expression that fails when rendering
- `PhoenixVapor.Volt` — Volt plugin resolving `phoenix_vapor` imports from a path or umbrella dependency

### Compiler
- `PhoenixVapor.Compiler` — compiles a template and resolves the components it uses
- `PhoenixVapor.Compiler.Split` — `Vize.split_template/2` output → `PhoenixVapor.Template`
- `PhoenixVapor.Compiler.SFC` — `.vue` file paths, the `<template>` block, `<script lang="elixir">`
- `PhoenixVapor.Compiler.ScriptSetup` — what `<script setup>` declares
- `PhoenixVapor.Compiler.Macros` — `with { type: "macro" }` calls run at compile time
- `PhoenixVapor.Compiler.PropTypes` — prop types from TypeScript's checker, for macro calls
- `PhoenixVapor.Compiler.Packages` — package components rendered with Vue's server renderer at compile time

### Renderer
- `PhoenixVapor.Renderer` — `PhoenixVapor.Template` → `%Rendered{}`
- `PhoenixVapor.Renderer.Expr` — JS expression evaluation in Elixir
- `PhoenixVapor.Renderer.Attrs` — dynamic attributes as Vue's server renderer writes them
- `PhoenixVapor.Renderer.Names` — atoms for declared names, never created while rendering

### Modes
- `PhoenixVapor.Reactive` — reactive mode
- `PhoenixVapor.Reactive.Runtime` — QuickBEAM GenServer for reactive state
- `PhoenixVapor.Hybrid` — hybrid mode
- `PhoenixVapor.Hybrid.Classifier` — binding classification via AST
- `PhoenixVapor.Hybrid.ServerCodegen` — Elixir code generation
- `PhoenixVapor.Hybrid.ClientCodegen` — Vue 3 JS generation
- `PhoenixVapor.Full` — the full runtime (`runtime: :full`)
- `PhoenixVapor.Full.Runtime` — QuickBEAM GenServer for the full Vue runtime

### JavaScript
- `PhoenixVapor.JS` — QuickBEAM runtimes and contexts, `priv/ts` templates, and bundling with Volt
- `PhoenixVapor.JS.EntryPlugin` — Volt plugin serving a generated entry module
- `Mix.Tasks.PhoenixVapor.Bundle` — bundles a Vue component library for the full runtime

### TypeScript (`priv/ts`)
- `reactive/runtime.ts` — reactive mode's runtime in QuickBEAM, bundled with the vendored `@vue/reactivity` at compile time
- `browser/live-socket.ts` — `patchLiveSocket`, direct DOM writes for value-only diffs (`phoenix_vapor`)
- `browser/vapor-patch.ts` — slot analysis and DOM writes behind it (`phoenix_vapor/vapor-patch`)
- `browser/hybrid-bridge.ts` — LiveView hook for hybrid components (`phoenix_vapor/hybrid`)
- `compile/packages.ts` — renders package components with `vue/server-renderer`, for `PhoenixVapor.Compiler.Packages`
- `compile/prop-types.ts` — prop types from TypeScript's checker, for `PhoenixVapor.Compiler.PropTypes`
- `compile/macros/entry.ts`, `compile/macros/call.ts` — load macro modules and evaluate a call
- `compile/globals.d.ts` — the placeholders and globals those share
