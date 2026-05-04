# PhoenixVapor Hybrid Architecture

One `.vue` file. The compiler decides what runs where. No LiveView leakage. Instant local UI. Server-authoritative domain state.

---

## The Idea in 30 Seconds

You write a normal Vue SFC:

```vue
<script setup>
import { ref, computed } from "vue"

defineProps(["users"])              // comes from the server (DB, assigns)
const search = ref("")             // lives in the browser (instant)
const filtered = computed(() =>    // derived from both — runs on client
  users.filter(u => u.name.includes(search.value))
)

function clearSearch() {           // pure client — no network
  search.value = ""
}

function deleteUser(id) {          // needs the server
  "use server"
  users = users.filter(u => u.id !== id)
}
</script>

<template>
  <input v-model="search" />
  <p>{{ filtered.length }} results</p>
  <li v-for="user in filtered" :key="user.id">
    {{ user.name }}
    <button @click="deleteUser(user.id)">×</button>
  </li>
  <button @click="clearSearch">Clear</button>
</template>
```

The compiler reads this file and produces:

- **Server (Elixir)**: `mount/3`, `render/1`, `handle_event("deleteUser", ...)`
- **Client (JS)**: Vue Vapor reactive render with `ref`, `computed`, `renderEffect`
- **Bridge**: LiveView diffs flow into a `shallowRef` → Vue reactivity does the rest

No `$live.pushEvent`. No `phx-hook`. No wrapper divs. No `phx-update="ignore"`.

---

## How Classification Works

The compiler looks at your `<script setup>` and applies simple rules:

| What you wrote | What the compiler sees | Classification |
|---|---|---|
| `defineProps(["users"])` | Data from LiveView assigns | **Server prop** (read-only on client) |
| `ref("")` | Local reactive state | **Client ref** (instant, no network) |
| `computed` using a prop | Derivation needing server data | **Mixed computed** (runs on client, reads server + client) |
| `computed` using only refs | Pure local derivation | **Client computed** |
| Function writing only to refs | `clearSearch()` | **Client handler** (no wire) |
| Function writing to a prop | `banUser()` | **Server action** (auto-detected) |
| Function with `"use server"` | `deleteUser()` | **Server action** (explicit) |

No annotations needed for 90% of cases. `"use server"` is the escape hatch for ambiguous ones (functions that need the server but don't visibly write to props — like sending an email).

---

## Wire Protocol: The Best of Both Worlds

### Initial render

The server sends a standard LiveView rendered payload — statics + dynamics — with one addition: the `"c"` key carries client bootstrapping data.

```json
{
  "s": ["<div><input value=\"", "\"/><p>", "</p><ul>", "</ul><button>Clear</button></div>"],
  "0": "",
  "1": "5 results",
  "2": "<li>Alice</li><li>Bob</li><li>Carol</li><li>Dave</li><li>Eve</li>",
  "c": {
    "props": { "users": [{"id":1,"name":"Alice"}, {"id":2,"name":"Bob"}, ...] },
    "refs": { "search": "", "page": 1 },
    "clientSlots": [0, 1, 2]
  }
}
```

- **`"s"`** — statics (the HTML skeleton, sent once, cached forever)
- **`"0"`, `"1"`, `"2"`** — initial slot values (server renders everything on first paint for SEO/instant display)
- **`"c"`** — client manifest:
  - `props` — server data the client needs for its computeds
  - `refs` — initial client state (so the client can pick up where it left off on reconnect)
  - `clientSlots` — which slots the client will own after hydration

The browser shows the HTML immediately (server-rendered). Then the client JS loads, reads `"c"`, hydrates, and takes ownership of slots `[0, 1, 2]`.

### Client-only interaction (zero wire)

User types "Ali" in the search box:

```
keystroke → search.value = "Ali"
              │
              ▼ (Vue reactivity — computed recomputes)
         filtered = [Alice]
              │
              ├─→ setText(n1, "1 results")    // slot 1
              └─→ createFor re-renders list    // slot 2

Wire: nothing. Zero bytes. Instant.
```

The server doesn't know and doesn't care that the user is filtering. It's ephemeral UI state.

### Server prop update

Someone else adds a user (via PubSub) — the server's `users` assign changes:

```json
{
  "c": { "props": { "users": [...updated list...] } }
}
```

Client receives this, sets `__serverProps.value = newProps`, and Vue's reactivity does the rest:
- `filtered` recomputes (because it reads `users`)
- Affected `renderEffect`s fire
- DOM updates

Only the props payload travels the wire — not individual slot values. The client's reactive graph handles distribution to the right DOM nodes.

### Server action (event round-trip)

User clicks "Delete" on Bob:

```
click → deleteUser(2)
          │
          ├── Optimistic: remove Bob from local props → DOM updates instantly
          │
          └── pushEvent("deleteUser", {id: 2}) → WebSocket → server
                                                                │
                                                     handle_event runs
                                                     Repo.delete!(bob)
                                                     assign(users: [...])
                                                                │
                                                                ▼
                                                     diff: {"c": {"props": {...}}}
                                                                │
                                                                ▼
                                                     Client: overwrites props
                                                     (server always wins)
```

User sees deletion instantly. Server confirms (or corrects if permission denied).

### Server-only slot (pure LiveView efficiency)

Some slots only depend on server state and are never touched by client reactivity:

```vue
<header>{{ currentUser.name }}</header>
```

This is a **server-only slot** — rendered via standard LiveView positional diff:

```json
{"3": "Admin"}
```

8 bytes. Same efficiency as current PhoenixVapor. No client JS involved. No props serialization overhead.

### The split in one picture

```
Template expression          Who renders it?         Wire format
─────────────────────────── ─────────────────────── ───────────────────────────
{{ currentUser.name }}       Server (LV diff)        {"3": "Admin"}
{{ search }}                 Client (Vue Vapor)      nothing (client ref)
{{ filtered.length }}        Client (Vue Vapor)      nothing (client computed)
v-for="u in filtered"       Client (Vue Vapor)      nothing (client structural)
@click="clearSearch"         Client (event)          nothing
@click="deleteUser(id)"     Client → Server         pushEvent over WS
```

---

## What Runs Where

### Server (Elixir — no JS)

```
┌──────────────────────────────────────────┐
│ LiveView Process                         │
│                                          │
│  mount/3     → load from DB, set assigns │
│  render/1    → %Rendered{} with:         │
│                  - server-only slots     │
│                  - props JSON for client  │
│  handle_event → domain logic, re-assign  │
│                                          │
│  No QuickBEAM. No server-side JS.       │
│  Just Elixir.                            │
└──────────────────────────────────────────┘
```

### Client (Vue Vapor — real Vue)

```
┌──────────────────────────────────────────┐
│ Browser (~12KB runtime)                  │
│                                          │
│  @vue/reactivity:                        │
│    shallowRef(__serverProps)             │
│    ref(search), ref(page)               │
│    computed(filtered)                    │
│                                          │
│  Vue Vapor compiled output:             │
│    renderEffect(() => setText(...))      │
│    renderEffect(() => setAttr(...))      │
│    createFor(...)                        │
│    on(el, "click", handler)             │
│                                          │
│  Bridge:                                 │
│    onDiff → __serverProps.value = props  │
│    pushEvent → WebSocket                 │
└──────────────────────────────────────────┘
```

### Why Vue Vapor (not custom reactivity)

The generated client uses **real Vue primitives** — not a hand-rolled system:

```js
// ✅ Real Vue — devtools work, ecosystem composables work
import { ref, computed, shallowRef } from "@vue/reactivity"
import { renderEffect, setText, createFor } from "@vue/vapor"

const __serverProps = shallowRef({ users: [] })
const search = ref("")
const filtered = computed(() =>
  __serverProps.value.users.filter(u => u.name.includes(search.value))
)

renderEffect(() => setText(n1, filtered.value.length + " results"))
```

Vue Vapor's compiled output is already "direct DOM writes per reactive dependency" — the same philosophy as PhoenixVapor's slot-write model. We don't reinvent it.

---

## Reactivity: One Unified Graph

The client holds a single reactive dependency graph. Server data enters via a `shallowRef`:

```
Server diff arrives
       │
       ▼
__serverProps.value = { users: [...] }     ← triggers dependents
       │
       ├───→ filtered (computed)           ← recomputes
       │          │
       │          ├───→ renderEffect: setText(count)
       │          └───→ renderEffect: createFor(list)
       │
       └───→ renderEffect: setText(header) ← if reads props directly

Client keystroke
       │
       ▼
search.value = "Ali"                       ← triggers dependents
       │
       └───→ filtered (computed)           ← recomputes (same computed!)
                  │
                  ├───→ renderEffect: setText(count)
                  └───→ renderEffect: createFor(list)
```

A `computed` that reads both `__serverProps.value.users` and `search.value` reacts to **either** source automatically. No special wiring. This is standard Vue reactivity.

---

## State Sync Protocol

### Rules

1. **Server → Client**: Assigns change → re-render → diff with props → client `shallowRef` updates → Vue propagates
2. **Client → Server**: `"use server"` function called → `pushEvent` → server processes → new assigns → back to #1
3. **Client → Client**: Ref mutation → computed recomputation → `renderEffect` → DOM. No wire.
4. **Conflict**: Server response always overwrites `__serverProps`. Optimistic state is a temporary prediction.

### What the server sends (props serialization)

Only props that the client actually uses are serialized. The compiler knows this at build time:

```elixir
# Compiler determined: client reads `users` but not `currentUser`
# (currentUser is only in a server-only slot)
defp client_props(assigns) do
  %{users: assigns.users}
end
```

Props the client doesn't need never leave the server.

---

## `"use server"` Directive

Borrowed from React/Next.js. Marks a function as running on the server:

```vue
function deleteUser(id) {
  "use server"
  users = users.filter(u => u.id !== id)
}
```

**What happens:**
- Function body → compiled to Elixir `handle_event("deleteUser", %{"id" => id}, socket)`
- Client gets an async stub that applies the mutation optimistically + sends the event
- Server response overwrites optimistic state

**When you need it:**
- Function with side effects the client can't do (DB, email, auth)
- Function where the compiler can't tell it needs the server

**When you DON'T need it:**
- Function that writes to a prop → auto-detected as server action
- Function that only writes to client refs → auto-detected as client handler

```vue
// No directive needed — compiler sees it writes to `users` (a prop)
function banUser(id) {
  users = users.map(u => u.id === id ? { ...u, banned: true } : u)
}

// Directive needed — no visible prop write, but needs server
function sendInvite(email) {
  "use server"
  // This body only makes sense on the server
}

// No directive needed — only writes to client refs
function toggleMenu() {
  isOpen.value = !isOpen.value
}
```

---

## State Loss & Recovery

| Scenario | Server State | Client Refs | Result |
|----------|-------------|-------------|--------|
| **WebSocket blip** | Preserved (process alive) | Preserved (in memory) | Reconnect → server sends fresh props, client refs untouched |
| **Server crash** | Rebuilt from DB (mount/3) | Preserved (in memory) | Fresh props arrive, client refs survive |
| **Server deploy** | Same as crash | Preserved | Same as crash |
| **Tab background** | May timeout | Preserved | On return: reconnect, fresh props, refs OK |
| **Page reload** | Rebuilt from DB | **Lost** (JS memory gone) | Full fresh start. Opt-in: `persistedRef()` uses sessionStorage |
| **Client JS error** | Unaffected | May be corrupted | Server re-render restores correct DOM |

Compare to current PhoenixVapor (server-side QuickBEAM): process crash = ALL state lost (refs included). The hybrid is strictly better because client refs survive server failures.

---

## Compilation: Vue Vapor Integration

Vue Vapor already compiles templates into imperative DOM operations:

```vue
<p>{{ count }}</p>
```

Becomes:

```js
const t0 = template("<p></p>")
export function render(_ctx) {
  const n0 = t0()
  renderEffect(() => setText(n0, _ctx.count))
  return n0
}
```

This IS the PhoenixVapor slot-write model — but running on the client. We hook into Vue's compiler with a custom transform that knows the binding classification:

```ts
compile(templateAST, {
  nodeTransforms: [phoenixVaporTransform(bindings)],
  bindingMetadata: {
    users: BindingTypes.PROPS,          // reads from __serverProps
    search: BindingTypes.SETUP_REF,     // standard client ref
    filtered: BindingTypes.SETUP_REF,   // computed (exposed as ref)
  }
})
```

The transform:
- **Server-only expressions** → marked as "skip" (server handles via LV diff)
- **Client/mixed expressions** → standard Vue Vapor codegen
- **Event handlers** → routed to client handler or server action stub

Two compilation passes produce output for the same template:

| Pass | Tool | Output | Handles |
|------|------|--------|---------|
| Server | Vize (Rust) → `%Rendered{}` | Elixir rendered struct | Server-only slots + props payload |
| Client | Vue Vapor compiler → JS | Imperative DOM code | Client + mixed slots |

---

## Edge Cases

### Computed depends on both server and client

```vue
const filtered = computed(() => users.filter(u => u.name.includes(search.value)))
```

Runs on client. Reads `__serverProps.value.users` (server) and `search.value` (client). Recomputes on either change. Standard Vue — no special handling.

### Optimistic update rejected by server

Client removes item optimistically. Server responds with the original list (permission denied). `__serverProps.value` is overwritten → item reappears. Server always wins.

### v-model on a server prop

```vue
<input v-model="user.name" />
```

Bidirectional binding to server data:
- On input: optimistic local update + debounced pushEvent
- On server response: authoritative value overwrites

### Function calls something undefined

```vue
function doSomething() {
  mysteriousOperation(users)
}
```

Compiler warns: "Cannot classify `doSomething` — `mysteriousOperation` is undefined. Add `\"use server\"` if this requires the server."

### Large nested prop, single field changes

Server sends full props JSON (not leaf-level patch). But:
1. `shallowRef` only triggers if the top-level reference changes (which it does)
2. Computeds that don't read the changed path won't recompute (Vue's fine-grained tracking)
3. `renderEffect`s that didn't access the changed field won't fire

For very large objects, the bridge can adopt prop-level diffing:

```json
{"c": {"diff": {"user.address.city": "Berlin"}}}
```

Client applies the patch to existing props rather than replacing the whole object.

### Multiple components on one page

Each hybrid component is isolated: own `__serverProps`, own refs, own render tree. The bridge maps incoming diffs to the correct component by ID.

### Client animations and transitions

```vue
const entering = ref(false)
function show() {
  isVisible.value = true
  entering.value = true
  requestAnimationFrame(() => { entering.value = false })
}
```

Pure client. Zero server. Impossible with current PhoenixVapor where every state change round-trips.

### Ref that persists across page navigations

```vue
import { persistedRef } from "phoenix_vapor/client"
const sidebarOpen = persistedRef("sidebar", true)
```

Standard composable using `sessionStorage`. Survives reloads. The compiler doesn't need to know about it.

---

## Comparison: Three Systems

### Wire Efficiency

Counter going from 5 to 6:

| System | Wire payload | Size |
|--------|-------------|------|
| **PhoenixVapor** (server-only slot) | `{"0": "6"}` | 8 bytes |
| **Fronix/LiveVue** (JSON Patch) | `{"0":"{\"count\":6}","1":"[[\"test\",\"\",384],[\"replace\",\"/count\",6]]"}` | ~80 bytes |
| **Hybrid** (server-only slot) | `{"1": "6"}` | 8 bytes |
| **Hybrid** (client-computed input) | `{"c":{"props":{"count":6}}}` | ~25 bytes |
| **Hybrid** (pure client ref) | nothing | 0 bytes |

### Architecture

| | PhoenixVapor (current) | Fronix/LiveVue | Hybrid |
|---|---|---|---|
| **Client JS** | 0-2KB | ~50KB+ | ~12KB |
| **Server JS** | QuickBEAM (50KB-2MB/user) | None | None |
| **Local UI latency** | 1 RTT | 0 | 0 |
| **Server memory/user** | High | Low | Low |
| **State on crash** | All lost | Server rebuilds, client survives | Server rebuilds, client survives |
| **Wrapper divs** | None | Required | None |
| **DOM ownership** | LiveView | `phx-update="ignore"` | Split (server shell + client reactive) |
| **Wire format** | Native LV positional | Double-encoded JSON Patch | Native LV positional + props JSON |
| **Developer model** | Vue as template DSL | Two files (Elixir + Vue) | One file (Vue SFC) |
| **Framework ecosystem** | None | Full | Vue Vapor subset (composables, devtools) |
| **Multi-framework** | No (Vue syntax only) | Yes (Vue, React, Svelte) | No (Vue Vapor only) |
| **Event handling** | `phx-click` in HTML | `useLive().pushEvent(...)` | `"use server"` or auto-detected |

### Nested Props

Deep object, only `user.address.city` changes:

| System | What's sent | Why |
|--------|-------------|-----|
| **PhoenixVapor** | All slots touching `user` | Root-assign-level tracking (coarse) |
| **Fronix/LiveVue** | `["replace", "/user/address/city", "Berlin"]` | JSON Patch (precise) |
| **Hybrid** | Props JSON with updated user | shallowRef + Vue reactivity (only affected computeds recompute) |

---

## Client Bundle

```
@vue/reactivity            8KB  (ref, computed, shallowRef, effect)
Vue Vapor runtime          3KB  (template, renderEffect, setText, createFor, on)
Phoenix Vapor bridge       1KB  (__applyProps, pushEvent, hydrate)
────────────────────────────────
Total                     12KB  (min+gzip)
```

---

## Migration Path

The hybrid mode is **additive** — existing PhoenixVapor modes continue to work:

| Mode | Client JS | Use case |
|------|-----------|----------|
| `~VUE` sigil | 0KB | Vue syntax as template DSL, zero JS |
| `use PhoenixVapor.Reactive` | 0KB | Server-side reactivity (QuickBEAM) |
| `use PhoenixVapor.Hybrid` | 12KB | Split reactivity, instant client UI |

Phases:
1. Ship the bridge module (receive prop diffs into a `shallowRef`)
2. Add `"use server"` support to script analysis
3. Integrate Vue Vapor compiler for client template output
4. Automatic binding classification (no manual hints needed)

---

## Summary

Write one `.vue` file. The compiler splits it:

- **`defineProps`** → server-owned, flows down via LiveView diffs
- **`ref()`** → client-owned, instant, never touches the wire
- **`computed`** → runs wherever its dependencies require
- **`"use server"`** → function body becomes Elixir `handle_event`
- **Everything else** → auto-detected from dataflow analysis

Server owns the truth. Client owns the speed. The wire carries the minimum. Vue Vapor renders the DOM.
