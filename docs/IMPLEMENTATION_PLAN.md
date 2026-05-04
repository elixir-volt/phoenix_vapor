# Hybrid Mode Implementation Plan

## Current Assets We Keep

| Module | Role | Status |
|--------|------|--------|
| `PhoenixVapor` | Main entry, `~VUE` sigil mode | Keep unchanged |
| `PhoenixVapor.Sigil` | Compile-time `~VUE` | Keep unchanged |
| `PhoenixVapor.Renderer` | Vapor IR → `%Rendered{}` | Keep, extend for hybrid slots |
| `PhoenixVapor.Expr` | JS expression eval in Elixir | Keep (used for server-only slots) |
| `PhoenixVapor.Component` | Component helpers | Keep |
| `PhoenixVapor.Vue` | `.vue` file loading | Keep |
| `PhoenixVapor.ScriptSetup` | Parse `<script setup>` | **Extend** (add classification) |
| `PhoenixVapor.Reactive` | Server-side reactivity | Keep as separate mode |
| `PhoenixVapor.Runtime` | QuickBEAM GenServer | Keep (used by Reactive mode) |
| `PhoenixVapor.LiveVue` | Full Vue runtime | Keep as separate mode |
| `PhoenixVapor.VueRuntime` | QuickBEAM for full Vue | Keep |

## New Modules

| Module | Role |
|--------|------|
| `PhoenixVapor.Hybrid` | `__using__` macro — the main entry point |
| `PhoenixVapor.Hybrid.Classifier` | Analyze script → classify bindings |
| `PhoenixVapor.Hybrid.ServerCodegen` | Generate Elixir (mount, render, events) |
| `PhoenixVapor.Hybrid.ClientCodegen` | Generate JS (Vue Vapor-style reactive render) |
| `PhoenixVapor.Hybrid.Props` | Props serialization + diffing logic |

## New Client JS

| File | Role | Size |
|------|------|------|
| `priv/js/hybrid-bridge.js` | Receive LV diffs → update shallowRef, pushEvent wrapper | ~1KB |

## Phases

### Phase 1: Classifier

**Goal**: Given a parsed `<script setup>`, produce a binding classification map.

**Input** (already available from `ScriptSetup.parse`):
```elixir
%{
  props: ["users", "currentUser"],
  refs: %{"search" => ~s(""), "page" => "1"},
  computeds: %{"filtered" => "users.filter(...)"},
  functions: ["clearSearch", "deleteUser"],
  function_bodies: %{"clearSearch" => "...", "deleteUser" => ~s("use server"; ...)}
}
```

**Output**:
```elixir
%{
  bindings: %{
    "users" => :server_prop,
    "currentUser" => :server_prop,
    "search" => {:client_ref, ~s("")},
    "page" => {:client_ref, "1"},
    "filtered" => {:mixed_computed, server_deps: ["users"], client_deps: ["search"]},
  },
  handlers: %{
    "clearSearch" => :client_handler,
    "deleteUser" => {:server_action, body: "users = users.filter(u => u.id !== id)"}
  },
  client_props: ["users"],       # server props the client needs
  server_only_props: ["currentUser"]  # server props only used in server slots
}
```

**Implementation**:
1. Props from `defineProps` → `:server_prop`
2. Refs → `:client_ref`
3. Computeds → analyze expression deps (which identifiers does it reference?)
   - All deps are client refs → `:client_computed`
   - Any dep is a server prop → `:mixed_computed`
4. Functions:
   - Body starts with `"use server"` → `:server_action`
   - Body writes to a prop name (LHS assignment to a prop identifier) → `:server_action`
   - Otherwise → `:client_handler`

**Files**: `lib/phoenix_vapor/hybrid/classifier.ex`

---

### Phase 2: Server Codegen

**Goal**: From the classification + template, generate Elixir code for mount/render/handle_event.

**Key decisions**:
- `render/1` produces a `%Rendered{}` with:
  - Server-only slots rendered normally (via `PhoenixVapor.Renderer`)
  - A special "props" slot containing JSON of client-consumed props
  - Client-owned regions as empty placeholder strings
- `handle_event/3` clauses generated for each server action

**Template slot classification** (needs template analysis too):
- For each slot in the Vapor IR, determine if it references any client binding
- If purely server → server renders it (positional diff)
- If touches any client binding → client renders it (server sends empty placeholder)

**Simplified initial approach** (Phase 2a):
- Server renders the FULL initial HTML (all slots) for first paint / SEO
- Server also sends the props JSON in a data attribute or dedicated slot
- On update, server only sends the props slot (client handles the rest)

**Files**: `lib/phoenix_vapor/hybrid/server_codegen.ex`

---

### Phase 3: Client Codegen

**Goal**: Generate a JS module that hydrates and manages client-owned slots.

**Output shape**:
```js
import { ref, computed, shallowRef, triggerRef } from "@vue/reactivity"

// Server props
const __props = shallowRef({})

// Client refs
const search = ref("")
const page = ref(1)

// Computeds
const filtered = computed(() =>
  (__props.value.users || []).filter(u => u.name.includes(search.value))
)

// Client handlers
function clearSearch() { search.value = ""; page.value = 1 }

// Server actions
function deleteUser(id) {
  __props.value = { ...__props.value, users: __props.value.users.filter(u => u.id !== id) }
  triggerRef(__props)
  __bridge.pushEvent("deleteUser", { id })
}

// Reactive DOM bindings (simplified — not full Vue Vapor yet)
export function mount(container, bridge) {
  // ... slot bindings
}

export function applyProps(props) {
  __props.value = props
}
```

**Phase 3a** (no Vue Vapor compiler — hand-generated reactive bindings):
- Generate `renderEffect`-equivalent code using `@vue/reactivity`'s `effect()`
- Target specific DOM nodes by data attributes or nth-child paths
- Similar to current `vapor_patch.js` but reactive

**Phase 3b** (Vue Vapor compiler integration):
- Feed template + binding metadata into `@vue/compiler-vapor`
- Use its output directly

**Files**: `lib/phoenix_vapor/hybrid/client_codegen.ex`

---

### Phase 4: Bridge JS

**Goal**: Tiny client module that connects LiveView diffs to the generated reactive code.

```js
// priv/js/hybrid-bridge.js
export function createBridge(liveSocket, elementId, component) {
  const el = document.getElementById(elementId)
  
  // Read initial props from data attribute
  const initialProps = JSON.parse(el.dataset.pvProps)
  component.applyProps(initialProps)
  
  // Mount reactive DOM
  component.mount(el, {
    pushEvent: (event, params) => {
      // Find the LiveView hook and push
      const hook = liveSocket.getHookByEl(el)
      hook.pushEvent(event, params)
    }
  })
  
  return {
    // Called by LiveView hook on update
    onDiff(newProps) {
      component.applyProps(newProps)
    }
  }
}
```

**Files**: `priv/js/hybrid-bridge.js`

---

### Phase 5: `PhoenixVapor.Hybrid` Macro

**Goal**: The user-facing entry point that wires everything together.

```elixir
defmodule MyAppWeb.UsersLive do
  use MyAppWeb, :live_view
  use PhoenixVapor.Hybrid, file: "Users.vue"
end
```

The macro:
1. Reads and parses the `.vue` file (Vize)
2. Runs the Classifier on `<script setup>`
3. Runs ServerCodegen → injects `mount/3`, `render/1`, `handle_event/3`
4. Runs ClientCodegen → writes JS file to build output
5. Renders template with appropriate slot assignments

**Files**: `lib/phoenix_vapor/hybrid.ex`

---

## Execution Order

```
Phase 1: Classifier              (pure analysis, easy to test in isolation)
    ↓
Phase 2: Server Codegen          (generates working Elixir — testable with existing test patterns)
    ↓
Phase 3a: Client Codegen (basic) (generate JS with @vue/reactivity effect())
    ↓
Phase 4: Bridge JS               (tiny glue code)
    ↓
Phase 5: Hybrid Macro            (wire it all together)
    ↓
Phase 3b: Vue Vapor compiler     (replace basic codegen with real Vue Vapor output)
```

## Testing Strategy

### Phase 1 tests (Classifier)
```elixir
test "classifies defineProps as server_prop" do
  classification = Classifier.classify(parsed_script)
  assert classification.bindings["users"] == :server_prop
end

test "classifies ref as client_ref" do
  assert classification.bindings["search"] == {:client_ref, ~s("")}
end

test "detects use server directive" do
  assert classification.handlers["deleteUser"] == {:server_action, body: "..."}
end

test "auto-detects server action from prop write" do
  # function banUser(id) { users = users.filter(...) }
  assert classification.handlers["banUser"] == {:server_action, body: "..."}
end

test "classifies mixed computed" do
  assert classification.bindings["filtered"] == {:mixed_computed, server_deps: ["users"], client_deps: ["search"]}
end
```

### Phase 2 tests (Server Codegen)
- Generate Elixir AST → compile → call mount/render/handle_event
- Verify `%Rendered{}` has correct statics/dynamics
- Verify handle_event clauses exist for server actions

### Phase 3 tests (Client Codegen)
- Generate JS → verify it's valid (OXC.parse succeeds)
- Verify it contains the right imports, refs, computeds
- Eventually: run in QuickBEAM to verify reactive behavior

### Integration tests
- Full round-trip: `.vue` file → Hybrid macro → LiveView that responds to events
- Verify server-only slots render correctly
- Verify props JSON is included in render output

## Key Discovery: Vize 0.10 Already Outputs Vue Vapor Code

`Vize.compile_sfc!(source, vapor: true)` produces a complete Vue Vapor component:
- `defineVaporComponent` wrapper
- `setup()` with refs, computeds, handlers from `<script setup>`
- `render()` with `renderEffect`, `setText`, `setProp`, `createFor`, etc.
- All in one Rust NIF call — no Node.js needed

This means **Phase 3b (Vue Vapor compiler) is already done by Vize**.

The client codegen becomes:
1. Run `Vize.compile_sfc!(source, vapor: true)` → get complete Vue Vapor JS
2. Post-process: rewrite `_ctx.propName` access to `__serverProps.value.propName`
3. Inject the bridge import and server action stubs
4. Done — the output is a working Vue Vapor component

The entire compilation pipeline stays in Rust NIFs via Vize + OXC.

## What We DON'T Build Yet

- Full Vue devtools integration
- `persistedRef()` composable
- Multi-component communication
- LiveStream integration in props
- Prop-level diffing (start with full JSON replacement)
- Production bundling of generated client JS (use Volt for this later)
