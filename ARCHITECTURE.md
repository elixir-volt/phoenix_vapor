# Architecture

PhoenixVapor compiles Vue template syntax into native LiveView rendered trees. Four progressive modes share a common foundation: a template is static HTML with dynamic slots between it, the shape of a LiveView rendered diff, and of Vue's Vapor mode, which the project is named after.

That shape is rendered on the server. Vapor mode itself runs nowhere: templates are split by Vize (`Vize.split_template/2`, built on its semantic IR), and in the browser hybrid components are standard Vue 3 components on the virtual DOM. See [Why standard Vue in the browser](#why-standard-vue-in-the-browser).

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

- Most expressions (`{{ count }}`, `item.name`, comparisons, arithmetic, ternaries) → Elixir, over the OXC AST, with JavaScript's semantics for truthiness, equality and coercion (`PhoenixVapor.Renderer.Value`)
- What only JavaScript can evaluate (`.filter()` with a callback, `Math.max`) → QuickBEAM on every render, reported as a warning when compiling
- Macro calls and package components → run once in QuickBEAM while compiling, or once for each value of what they read when TypeScript types it as a set of literals, so rendering them runs no JavaScript
- Change tracking: on each render, a slot is re-evaluated only when an assign its expression reads is in `__changed__`

## Mode 1: `~VUE` Sigil

Vue syntax as a template DSL. Zero client JS.

```
Template → Vize.split_template → PhoenixVapor.Template → %Rendered{} → LiveView diff → morphdom
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
    → Client: Vue 3 component module on the virtual DOM (<Name>.hybrid.js)
    → Bridge: LiveView hook syncs props via data-pv-props
```

The compiler analyzes `<script setup>` and classifies each binding:

| Pattern | Classification |
|---------|---------------|
| `defineProps(["x"])` | Server prop, read-only in the browser |
| `defineModel("x")` | Model: a server prop the browser may change |
| `ref(value)` | Client ref |
| `computed` using any prop | Mixed computed |
| Function with `"use server"` | Server action |
| Function writing a model's `.value` | Server action (auto-detected) |
| Function writing only to refs | Client handler |

A server action's body runs in the browser as written, and the action is sent after it, through the bridge's `action/2`, so a `return` or `throw` in the body sends nothing. The generated `__mount` passes an `onUpdate:<model>` listener per model, so a model write updates the mount's props at once. The action's params are taken as JSON when it's called, before the body runs. `action/2` pushes the event and counts it in flight; LiveView settles the push after applying the action's diff, and when the last action in flight settles, answered or failed, the hook reapplies `data-pv-props`: an assign the server changed is already there, and one it left unchanged replaces the optimistic value. `updated()` waits while actions are in flight, so one action's answer doesn't undo another's optimistic change. Because the body runs in the browser, the props it reads are client props. A write to `props.x`, or to a prop name the script never binds (`JS.FreeNames.occurrences/1`), is a compile error (`Hybrid.build`).

Server renders full HTML for first paint (SEO). The hook then mounts the Vue component with `createApp` in place of that HTML; the wrapper is `phx-update="ignore"`, so later server renders don't touch the DOM Vue owns. Client interactions (search, sort, select) are instant — zero network. Server actions send events over the existing LiveView WebSocket.

### Why standard Vue in the browser

The generated client is compiled by Vize as an ordinary Vue 3 component and mounted with `createApp`; it doesn't use Vapor mode. That is a decision, not a gap:

- Component libraries such as Reka UI are virtual-DOM components. A Vapor client reaches them only through Vue's interop layer, which loads the virtual-DOM runtime anyway.
- Package components fold at compile time through Vue's server renderer (`vue/server-renderer`), which is the virtual-DOM one.
- Vapor mode arrived with Vue 3.6 and is much newer than the virtual-DOM runtime the libraries are tested against.

What this gives up is hydration: the browser mounts fresh in place of the server's first paint rather than adopting it. A Vapor client, whose output lines up with the server's statics and slots, is the way to get that, and is worth revisiting as Vapor mode matures. Anything that reaches into the client, such as session recording, should therefore depend on what the template reads, not on how the client renders.

### Wire Protocol

Initial render: server sends statics + dynamics, with the props JSON as the wrapper's `data-pv-props` dynamic. Updates: the props JSON travels only when a client prop changed. Client-only changes (typing in search) produce zero wire traffic.

### State Sync

- **Server → Client**: LiveView assign changes → re-render → diff with props JSON → hook's `updated()` → the instance's `applyProps()` → Vue reactivity propagates
- **Client → Server**: server action → its body runs (a model write updates the props at once) → `pushEvent` → `handle_event` → assign change → back to step 1
- **Client → Client**: `ref` mutation → computed recomputation → Vue re-render. No wire.

### Hybrid Computeds

`Hybrid.Computeds.compile/2` decides, in dependency order, how the server gets each computed: once while compiling when it reads only refs, on every render when it reads props, through its `<script lang="elixir">` counterpart when there is one, or not at all when it reads something only the browser has, such as a composable's result (`ScriptSetup.client_bindings`) or an import. A left-out computed is passed to the compiler as `:browser_only`: an expression reading it is unrendered, and a `v-if` chain stops at an unrendered condition. A counterpart's reads come from its source (`SFC.elixir_reads/3`): keys in its patterns and `assigns.key` are required, and rendering skips a counterpart missing one, as `__absent__` says; `assigns[:key]` is optional. All of them are recorded.

### Session Replay

PhoenixReplay (0.6) renders a recorded view from its recorded assigns alone; the QuickBEAM runtimes of Reactive mode and the full runtime live in `socket.private`, out of the recording. A hybrid component's client state lives in the browser. `Hybrid.build` works out which of it the server's render reads (the template, and the computeds and Elixir counterparts it reads), and setup registers those names; `browser/hybrid-bridge.ts` reports them as `phx_replay:state` window events between `phx_replay:start` and `phx_replay:stop` (or while `<html data-phx-replay>` says a recording is running), all of them on start and then the latest value of what changed, through a watcher per name, once it has been still for the replayer's `debounce` and at least once per `flush`, under `phoenix_vapor:<wrapper id>`; `sendAction` flushes them before a server action. The generated `replay_render/1` (`Hybrid.ServerCodegen.build_rendered/3` in `:replay` mode), the optional callback of `PhoenixReplay.Replay.View`, reads them from `@phoenix_replay_state` and renders without the client hook. PhoenixReplay renders it in full at every step, with `__changed__: nil`, which the renderer takes as every slot changed, as LiveView does, also when LiveView then diffs the result with change tracking. Rendering finds recorded names' atoms with `Names.existing/1`; the render spec lists every declared name's atom, so they're literals of the compiled module and exist on a server that never compiled the component. See the Hybrid guide.

### Package Components per Value

`Compiler.Packages.fold/6` renders a package component and the package components inside it with Vue's server renderer (`compile/packages.ts`, which appends what the render teleported and forces `forceMount` on `...Portal` components that declare it, as Reka's teleport only once mounted), into a `:fragment` slot whose template holds the SFC's own content as holes; the slot keeps the folded props' expressions as `:reads`, which change tracking, `Renderer.assign_keys/1`, `Renderer.reads/1` and so the recorded set count, though rendering doesn't evaluate them. `Packages.inputs/4` lists the expressions among them that read anything but the compile's `:constants`; `PropTypes.expression_values/3` types them with TypeScript's checker, appending them to the script in a function whose parameters are the script's bindings as `ShallowUnwrapRef` unwraps them, and the props. When each is a set of literals and there are at most 64 combinations (`Macros.combinations/2`), the compiler folds once per combination, with the values given to `fold/6` in `known`, into a `:fragments` slot, `%{inputs: [expr], table: %{[value] => template}}`; rendering evaluates the inputs, normalized by `Expr.literal/1`, and renders the template they key; an input reading absent state (`Expr.absent?/2`) renders nothing, and values outside the table render the `:initial` variant, the one for the values at compile time, with a logged warning. Otherwise it folds once with the initial values and reports why, at `:unrendered`. A child `.vue` component gets the parent's expressions for the props it's passed from state (`:passed`), and an input that reads such a prop or model whole takes the parent expression's values.

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
- `PhoenixVapor.Compiler.PropTypes` — prop and expression types from TypeScript's checker, for macro calls and package components, in one QuickBEAM runtime per TypeScript install that compiles in the VM share; it re-reads a file once its mtime changes
- `PhoenixVapor.Compiler.Packages` — package components rendered with Vue's server renderer at compile time

### Renderer
- `PhoenixVapor.Renderer` — `PhoenixVapor.Template` → `%Rendered{}`
- `PhoenixVapor.Renderer.Expr` — JS expression evaluation in Elixir
- `PhoenixVapor.Renderer.Value` — JavaScript's semantics for values: truthiness, equality, coercion, display
- `PhoenixVapor.Renderer.Attrs` — dynamic attributes as Vue's server renderer writes them
- `PhoenixVapor.Renderer.Names` — atoms for declared names, never created while rendering

### Modes
- `PhoenixVapor.Reactive` — reactive mode
- `PhoenixVapor.Reactive.Runtime` — QuickBEAM GenServer for reactive state
- `PhoenixVapor.Hybrid` — hybrid mode
- `PhoenixVapor.Hybrid.Classifier` — binding classification via AST
- `PhoenixVapor.Hybrid.Computeds` — `computed()` values for the server's render
- `PhoenixVapor.Hybrid.ServerCodegen` — Elixir code generation
- `PhoenixVapor.Hybrid.ClientCodegen` — Vue 3 JS generation
- `PhoenixVapor.Full` — the full runtime (`runtime: :full`)
- `PhoenixVapor.Full.Runtime` — QuickBEAM GenServer for the full Vue runtime

### JavaScript
- `PhoenixVapor.JS` — QuickBEAM runtimes and contexts, `priv/ts` templates, and bundling with Volt
- `PhoenixVapor.JS.EntryPlugin` — Volt plugin serving a generated entry module
- `PhoenixVapor.JS.Session` — the QuickBEAM runtime a compile uses for macros and package components
- `PhoenixVapor.JS.FreeNames` — the names a JavaScript expression reads
- `Mix.Tasks.PhoenixVapor.Bundle` — bundles a Vue component library for the full runtime

### TypeScript (`priv/ts`)
- `reactive/runtime.ts` — reactive mode's runtime in QuickBEAM, bundled with the vendored `@vue/reactivity` at compile time
- `browser/live-socket.ts` — `patchLiveSocket`, direct DOM writes for value-only diffs (`phoenix_vapor`)
- `browser/vapor-patch.ts` — slot analysis and DOM writes behind it (`phoenix_vapor/vapor-patch`)
- `browser/hybrid-bridge.ts` — LiveView hook for hybrid components (`phoenix_vapor/hybrid`)
- `compile/packages.ts` — renders package components with `vue/server-renderer`, for `PhoenixVapor.Compiler.Packages`
- `compile/prop-types.ts` — prop and template expression types from TypeScript's checker, for `PhoenixVapor.Compiler.PropTypes`
- `compile/macros/entry.ts`, `compile/macros/call.ts` — load macro modules and evaluate a call
- `compile/globals.d.ts` — the placeholders and globals those share
