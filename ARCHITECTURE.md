# PhoenixVapor Architecture

PhoenixVapor blends Phoenix LiveView and Vue along three layers:

1. **Vue template syntax compiled to native LiveView rendered trees**
2. **Optional server-side Vue reactivity via lightweight QuickBEAM contexts**
3. **Optional Vapor-native DOM patching on the client**

The goal is not to embed Vue beside LiveView, but to exploit the structural similarities between **Vue/Vapor templates** and **LiveView rendered diffs** as deeply as possible.

PhoenixVapor keeps the strengths of both systems:

- **LiveView** owns lifecycle, transport, events, supervision, reconnects, domain integration, and authoritative application state
- **Server-side Vue reactivity** owns local UI state, computed values, and dependency-driven updates
- **Vapor-style statics/dynamics** provide a shared rendering model that can drive efficient server and client patching

---

# Server-side JS vs client-side JS

PhoenixVapor uses JavaScript in two very different places. Keeping them separate is essential.

## Server-side JS
Server-side JS runs inside **QuickBEAM** inside the BEAM process tree. It is used for:

- Vue reactivity (`ref`, `computed`, watchers, local handlers)
- optional full Vue runtime execution
- evaluating or precomputing reactive values for rendering
- maintaining per-LiveView local reactive state on the server

This JS is authoritative only for **local reactive UI state**.

Current server-side JS assets include:
- `priv/js/vue-reactivity.js`
- `priv/js/runtime-setup.js`
- bundles loaded by `PhoenixVapor.VueRuntime` such as `priv/js/reka-dialog.js`

Current Elixir entrypoints for server-side JS:
- `PhoenixVapor.Runtime`
- `PhoenixVapor.VueRuntime`
- `PhoenixVapor.Reactive`
- `PhoenixVapor.LiveVue`

## Client-side JS
Client-side JS runs in the browser. It is used for:

- standard Phoenix LiveView client behavior
- receiving diffs over the websocket
- applying DOM updates
- optional Vapor-specific direct DOM patching

This JS does **not** own authoritative application state. It is primarily a DOM patch engine and transport peer.

Current client-side JS assets include:
- `examples/demo/assets/js/app.js`
- `examples/demo/assets/phoenix_vapor/index.js`
- `examples/demo/assets/phoenix_vapor/vapor_patch.js`

## Why the distinction matters
PhoenixVapor is not a classic client-heavy Vue app. The Vue-like reactive brain can live **server-side** in QuickBEAM, while the browser remains mostly a LiveView client with an optionally smarter patch engine.

That means:
- local UI state may be owned by **server-side JS**
- authoritative domain state is owned by **Elixir/LiveView**
- the browser JS is mainly responsible for **DOM application**, not app authority

---

# High-level model

PhoenixVapor supports three progressively deeper modes.

## 1. Compiled template mode
Use Vue template syntax in a normal LiveView or component:

```elixir
def render(assigns) do
  ~VUE"""
  <div>
    <p>{{ count }}</p>
    <button @click="inc">+</button>
  </div>
  """
end
```

In this mode:

- the template is compiled at compile time into a Vapor split
- the split is rendered into `%Phoenix.LiveView.Rendered{}`
- expressions may be evaluated in Elixir
- LiveView assigns are the primary input state
- no persistent server-side JS runtime is required

This mode is the lightest integration path.

---

## 2. Reactive mode
Use a `.vue` Single File Component with `<script setup>` and `<template>`:

```elixir
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view
  use PhoenixVapor.Reactive, file: "Counter.vue"
end
```

In this mode:

- a lightweight **server-side QuickBEAM JS context** is started per LiveView
- Vue refs/computeds/functions are loaded into that runtime
- local reactive UI state is owned by the server-side JS runtime
- LiveView remains the lifecycle and transport host
- rendering is still integrated with LiveView’s rendered tree / diff model

This is the main deep-fusion mode.

---

## 3. Full Vue runtime mode
Mount a full Vue component runtime server-side:

```elixir
use PhoenixVapor.LiveVue,
  bundle: "priv/js/reka-dialog.js",
  setup: "..."
```

In this mode:

- full Vue runtime semantics are available in **server-side JS**
- server-side DOM is rendered in QuickBEAM
- HTML is fed back through LiveView render/update flow
- the browser still acts as a LiveView client

This mode is best for advanced Vue component libraries or full Vue semantics, but it is architecturally different from the more Vapor-native compiled/reactive path.

---

# Core architectural idea

PhoenixVapor is built on a key structural observation:

## LiveView and Vapor share the same deep shape
Both systems naturally split rendering into:

- **statics**: the stable template skeleton
- **dynamics**: the changing values inserted into that skeleton
- **structural subtrees**: conditionals, loops, nested renders
- **template identity**: stable fingerprints that make incremental updates possible

Because of this, a Vue/Vapor template can compile naturally into LiveView’s rendered representation:

- Vapor statics/dynamics → `%Phoenix.LiveView.Rendered{}`
- Vapor loops → `%Phoenix.LiveView.Comprehension{}`
- conditional branches → nested `%Rendered{}` values
- local changes → ordinary LiveView diffs

This is the primary integration seam.

---

# Ownership model

PhoenixVapor explicitly separates **authoritative application state** from **local reactive UI state**.

## LiveView owns
- process lifecycle
- channel/event transport
- reconnect and rehydration
- routing and params
- session/auth/current_user
- domain state and database-backed data
- validation and changesets
- PubSub/shared state
- authorization/security boundaries
- render protocol metadata

## Server-side Vue runtime owns
- `ref()` local UI state
- `computed()` derived state
- watchers/effects
- local event handlers
- local presentation state
- dependency graph for reactive invalidation

## Projection between them
- LiveView pushes external inputs into the server-side runtime
- the runtime exposes a render snapshot or fine-grained slot changes
- rendering consumes projected state, not multiple competing sources of truth

### Guiding rule
LiveView is the authoritative host for application state.  
The server-side Vue runtime is the authoritative host for local reactive UI state.

---

# State categories

## JS-owned state
Examples:
- open/closed flags
- selected tab
- local draft input
- local filters
- transient presentation state
- computed labels/counts/classes

In PhoenixVapor reactive mode, this means **server-side JS in QuickBEAM**.

## LiveView-owned state
Examples:
- records loaded from the database
- current user/session/permissions
- route params
- changeset results
- PubSub-driven updates
- collaborative/shared state

## Split state
Some UI derives from domain data:

- the base dataset is LiveView-owned
- the local view projection is owned by server-side JS

For example:
- list of orders from DB → LiveView
- local sort key / filter / expanded row ids → server-side JS
- filtered visible rows → server-side JS computed value

---

# Rendering architecture

PhoenixVapor rendering is organized around an intermediate representation derived from Vapor.

## Compile step
A Vue template is compiled into a split:

- `statics`
- `slots`

The split describes:
- the static HTML skeleton
- each dynamic insertion point
- structural nodes such as conditionals and loops

## Render step
The split is turned into a native LiveView rendered tree:

- scalar slots become dynamic values
- conditional branches become nested `%Rendered{}`
- loops become `%Comprehension{}`
- template identity becomes a fingerprint

This allows PhoenixVapor to participate directly in LiveView’s diff machinery.

---

# Server rendering modes

## Compiled mode
In compiled mode:

- assigns are the primary input
- simple expressions may be evaluated in Elixir
- the output is a `%Phoenix.LiveView.Rendered{}` tree
- LiveView computes and sends diffs normally
- the browser uses normal LiveView client behavior unless Vapor patching is enabled

This mode favors simplicity and compatibility.

## Reactive mode
In reactive mode:

- a **server-side QuickBEAM runtime** is started per LiveView
- refs/computeds/functions are initialized inside it
- external inputs from LiveView are pushed into the runtime
- template values are derived from the runtime state
- the render layer projects the current runtime state into rendered slots

Over time, reactive mode should move toward:
- server-side JS-owned slot invalidation
- server-side JS-owned dependency graphs
- finer-grained structural patch plans

instead of relying only on Elixir assign-level change detection.

---

# Reactive runtime architecture

Each reactive LiveView may own a lightweight QuickBEAM context containing:

- Vue reactivity runtime
- initial refs
- computed definitions
- local handlers
- external input bindings
- optional precompiled slot getters

## Runtime responsibilities
- initialize local reactive graph
- apply local UI mutations
- apply external updates from LiveView
- recompute computed values
- expose renderable state
- eventually expose changed slots / branch ops / list ops

## LiveView responsibilities
- start/stop the runtime
- own supervision boundaries
- dispatch browser events
- decide whether an event is local, server, or hybrid
- synchronize authoritative external state into the runtime
- package render output into LiveView-compatible diffs

---

# Event model

PhoenixVapor distinguishes three event classes.

## 1. Local events
Examples:
- increment local counter
- toggle modal
- change local filter
- expand/collapse row

Handled entirely by the **server-side JS reactive runtime**.

Flow:
1. browser sends event
2. LiveView dispatches to server-side JS runtime
3. runtime mutates refs/computeds
4. runtime exposes updated render state
5. LiveView sends diff

## 2. Server events
Examples:
- save record
- delete item
- submit validated form
- query database
- subscribe/unsubscribe

Handled by LiveView/Elixir.

Flow:
1. browser sends event
2. LiveView handles domain logic
3. LiveView pushes updated external state into runtime if needed
4. runtime recomputes local derived state
5. LiveView sends diff

## 3. Hybrid events
Examples:
- optimistic UI update
- pending submit state
- local mutation followed by server action

Handled in both places:
1. server-side JS updates local UI state
2. LiveView performs authoritative server action
3. authoritative results overwrite mirrored state if needed

---

# Rehydration and restart

Because the server-side JS runtime owns local UI state, restart behavior must be explicit.

## On mount
LiveView initializes the runtime with:
- initial refs
- computed definitions
- handlers
- external props/params/session-derived inputs

## On external update
LiveView pushes authoritative changes into the runtime:
- props
- domain snapshots
- validation errors
- route changes

## On reconnect or runtime restart
LiveView recreates the runtime and rehydrates it from authoritative external state.

Initially, PhoenixVapor may choose to:
- rebuild local JS state from initialization only
- recompute all derived state

Later, selected server-side JS-owned refs may be serialized and restored if preserving local state across reconnects becomes a goal.

---

# Client patch architecture

PhoenixVapor can optionally optimize the last-mile DOM update step in the **browser**.

## Stock LiveView path
Normally, browser-side LiveView JS:
- merges incoming diffs into rendered state
- materializes HTML
- uses morphdom to update the DOM

## Vapor patch path
For Vapor-tagged roots, browser-side PhoenixVapor JS can:
- identify the static skeleton
- build a slot-to-DOM registry
- write updated slot values directly to text nodes/attributes
- skip generic morphdom work for eligible updates

This is possible because the server and client already share the statics/dynamics model.

---

# Current state of Vapor DOM patching

The current browser patcher is a prototype of a deeper rendering mode.

It demonstrates that:

- LiveView diffs can drive direct slot patching
- morphdom is unnecessary for some classes of updates
- Vapor metadata can be used to recover DOM patch targets

Today, this path is best viewed as **experimental**.

The long-term direction is to move from:
- browser-side inference from raw statics
- monkey-patching LiveView internals

toward:
- explicit server-generated slot metadata
- a first-class patch engine
- optional LiveView client tweaks or a dedicated integration layer

---

# Wire protocol

PhoenixVapor should be understood as using a layered protocol model.

## 1. Transport and session protocol
This layer handles:
- websocket join and reconnect
- heartbeats
- browser → server event pushes
- server → browser replies
- navigation/lifecycle concerns

PhoenixVapor currently reuses the standard LiveView transport/session protocol.

## 2. Render diff protocol
This layer handles:
- template identity and fingerprints
- statics and dynamic slots
- conditionals, loops, and nested renders
- component or subtree boundaries
- incremental update payloads

### Current state
Today, PhoenixVapor mostly reuses the standard LiveView render diff protocol by producing native `%Phoenix.LiveView.Rendered{}` and `%Phoenix.LiveView.Comprehension{}` values on the server. LiveView then serializes ordinary diffs over the wire.

That means PhoenixVapor currently does **not** define a separate websocket diff format. Instead, it defines a new way to generate LiveView-compatible rendered trees.

### Current Vapor-specific metadata
Today, the browser-side Vapor patch prototype needs extra structure beyond the raw LiveView diff. That extra structure is currently carried **out-of-band in the DOM**, not in the wire payload itself.

Current examples:
- `data-vapor`
- `data-vapor-statics`

The current model is therefore:
- **wire payload**: standard LiveView diff
- **DOM metadata**: Vapor-specific static structure hints
- **browser patcher**: combines both to attempt direct slot patching

### Why this is transitional
This approach proves the concept, but it asks the browser to infer too much from DOM metadata and LiveView internals. It is suitable for an experimental prototype, but it is not the ideal long-term protocol design.

## 3. DOM patch protocol
This layer handles how browser-side JS turns a diff/update payload into real DOM mutations.

### Stock LiveView path
- merge rendered diff state
- materialize HTML
- patch DOM with morphdom

### Vapor path
- identify a Vapor-aware root
- resolve slot targets
- apply direct scalar slot writes where possible
- apply structural branch/list updates when supported
- fall back when necessary

Today, the browser-side Vapor patcher is experimental and relies on DOM metadata plus patched LiveView client behavior.

## Long-term direction
PhoenixVapor does not need to preserve stock LiveView internals unchanged forever. If deeper integration requires tweaking or forking LiveView, that is an acceptable direction.

The most likely long-term direction is **not** a completely separate websocket protocol. Instead, PhoenixVapor can keep the LiveView transport/event/session framing while evolving a Vapor-aware rendering subprotocol for selected roots.

That would mean:
- keeping LiveView transport and event semantics
- keeping the overall request/reply lifecycle
- specializing rendered payload semantics for Vapor-aware roots
- making browser patch behavior explicit rather than inferred

Likely progression:

### Phase 1
- Vapor templates compile to native LiveView rendered trees
- browser fast path opportunistically patches scalar slots

### Phase 2
- server emits explicit Vapor root metadata
- server emits explicit slot descriptors or schema references
- browser patching becomes deterministic rather than heuristic

### Phase 3
- conditionals and loops gain first-class branch/list patch operations
- server-side JS runtime can contribute invalidation-aware patch payloads

### Phase 4
- Vapor patching becomes a supported render mode in a tweaked or forked LiveView client if needed

This keeps the LiveView transport stack while letting the rendering subprotocol become increasingly Vapor-native.

# Long-term protocol direction

The project does not aim to invent a completely separate transport protocol immediately. Instead, it builds on LiveView’s transport and diff model while gradually specializing the rendering layer.

The likely long-term progression is:

## Phase 1
- Vapor templates compile to native LiveView rendered trees
- browser fast path opportunistically patches scalar slots

## Phase 2
- server emits richer slot metadata
- browser patching becomes deterministic
- structural eligibility becomes explicit

## Phase 3
- conditionals and loops gain specialized patch plans
- branch swaps and keyed list ops become first-class

## Phase 4
- Vapor patching becomes a supported render mode in a tweaked or forked LiveView client if needed

This preserves LiveView’s strengths while allowing a deeper Vue/Vapor-native rendering engine to emerge.

---

# Why not just compile everything into assigns?

PhoenixVapor intentionally does not reduce Vue to syntax sugar over assigns.

That lighter path is useful for simple mode, but it leaves too much on the table:

- real computed semantics
- dependency-driven invalidation
- local reactive state graphs
- richer `<script setup>` support
- deeper alignment with Vue programming model

The server-side reactive runtime exists precisely to make the blend deeper than syntax translation.

---

# Why not let JS own everything?

PhoenixVapor also intentionally avoids giving full application authority to JS.

LiveView remains the canonical owner of:
- domain state
- persistence
- validation
- auth/security
- shared/distributed state
- reconnect/lifecycle

This keeps the architecture coherent and preserves the strengths of the BEAM.

---

# Summary

PhoenixVapor’s architecture is based on three principles:

## 1. Shared rendering shape
Vue/Vapor templates and LiveView rendered diffs are structurally compatible.  
PhoenixVapor uses that compatibility as the core integration seam.

## 2. Split state ownership
LiveView owns authoritative application state.  
The server-side Vue runtime owns local reactive UI state.

## 3. Progressive specialization
Start by reusing LiveView’s rendered tree and diff pipeline.  
Then progressively specialize the client/server rendering path where Vapor’s statics/dynamics model allows better performance or deeper semantics.

---

# Current module map

## Core template/render layer
- `PhoenixVapor`
- `PhoenixVapor.Sigil`
- `PhoenixVapor.Renderer`
- `PhoenixVapor.Expr`
- `PhoenixVapor.Component`
- `PhoenixVapor.Vue`

## Reactive runtime layer
- `PhoenixVapor.Reactive`
- `PhoenixVapor.Runtime`
- `PhoenixVapor.ScriptSetup`

## Full Vue runtime layer
- `PhoenixVapor.LiveVue`
- `PhoenixVapor.VueRuntime`

## Server-side JS assets
- `priv/js/vue-reactivity.js`
- `priv/js/runtime-setup.js`
- `priv/js/reka-dialog.js`

## Client-side JS prototype
- `examples/demo/assets/js/app.js`
- `examples/demo/assets/phoenix_vapor/index.js`
- `examples/demo/assets/phoenix_vapor/vapor_patch.js`

---

# Future work

## Near-term
- formalize render mode boundaries
- document state ownership clearly
- add protocol-level tests
- emit explicit slot metadata instead of relying on statics inference
- tighten reactive mode around server-side JS-owned canonical local state

## Mid-term
- move slot invalidation closer to the server-side JS dependency graph
- support structural patch plans for conditionals and keyed loops
- classify local vs server vs hybrid events explicitly

## Long-term
- establish a first-class Vapor patch mode in the LiveView client
- tweak or fork LiveView internals if necessary
- converge on a unified deep fusion model rather than a collection of partially overlapping modes
