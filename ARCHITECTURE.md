# Architecture

## Pipeline

```
                          compile time                              runtime
                    ┌────────────────────────┐          ┌───────────────────────────┐
                    │                        │          │                           │
Vue template ──────→  Vize.vapor_split/1     ├────────→ │ Renderer.to_rendered/2    │
                    │  (Rust NIF)            │          │ (Elixir)                  │
                    │                        │          │                           │
                    │  ┌──────────────────┐  │          │  ┌─────────────────────┐  │
                    │  │ parse tag tree   │  │          │  │ for each slot:      │  │
                    │  │ map element IDs  │  │          │  │   check __changed__ │  │
                    │  │ inject markers   │  │          │  │   eval expression   │  │
                    │  │ split on markers │  │          │  │   → string value    │  │
                    │  │ encode slots     │  │          │  └─────────────────────┘  │
                    │  └──────────────────┘  │          │             │             │
                    │           │            │          │             ▼             │
                    │           ▼            │          │  %Rendered{               │
                    │  %{statics, slots}     │          │    static: [...],         │
                    │  (embedded in BEAM     │          │    dynamic: fn,           │
                    │   module bytecode)     │          │    fingerprint: int       │
                    │                        │          │  }                        │
                    └────────────────────────┘          └─────────────┬─────────────┘
                                                                     │
                                                       enters LiveView diff engine
                                                       unchanged — same as ~H
```

## What goes over the wire

### First render (join)

Template: `<div><p :class="label">Count: {{ count }}</p></div>`

Assigns: `%{count: 0, label: "active"}`

The NIF splits the template into statics and slots:

```elixir
%{
  statics: ["<div><p class=\"", "\">", "</p></div>"],
  slots: [
    %{kind: :set_prop, values: ["label"]},
    %{kind: :set_text, values: [{:static_, "Count: "}, "count"]}
  ]
}
```

The renderer evaluates slots against assigns and produces:

```elixir
%Rendered{
  static: ["<div><p class=\"", "\">", "</p></div>"],
  dynamic: fn _ -> ["active", "Count: 0"] end,
  fingerprint: 94949380559044124300359658668089091771
}
```

LiveView's diff engine sends to the client:

```json
{
  "s": ["<div><p class=\"", "\">", "</p></div>"],
  "0": "active",
  "1": "Count: 0"
}
```

The client concatenates statics + dynamics into HTML, inserts via `innerHTML`.

### Subsequent update (diff)

User clicks increment. Server re-renders with `%{count: 1, label: "active", __changed__: %{count: true}}`.

The renderer checks each slot against `__changed__`:
- Slot 0 (`label`) — depends on `:label`, not in `__changed__` → `nil` (skip)
- Slot 1 (`Count: {{ count }}`) — depends on `:count`, in `__changed__` → `"Count: 1"`

```json
{"1": "Count: 1"}
```

8 bytes. Only the changed text, only the changed slot index.

Standard LiveView applies this by rebuilding the full HTML string and running morphdom. Vapor DOM applies it by writing `node.textContent = "Count: 1"` directly.

### v-if

Template: `<div><p v-if="show">{{ msg }}</p><p v-else>Hidden</p></div>`

When `show` is `true`:

```json
{
  "s": ["<div>", "</div>"],
  "0": {
    "s": ["<p>", "</p>"],
    "0": "Hello",
    "f": 119858224020869001705791094324100020391
  }
}
```

When `show` changes to `false`, the server sends a nested rendered with a **different fingerprint**:

```json
{
  "0": {
    "s": ["<p>Hidden</p>"],
    "f": 19949037608775884940587308270848430422
  }
}
```

The fingerprint change tells the client the template structure changed — it must replace the entire subtree, not patch individual values. This is the same mechanism LiveView uses for `if`/`case` in HEEx.

### v-for

Template: `<ul><li v-for="item in items">{{ item }}</li></ul>`

Assigns: `%{items: ["Elixir", "Vue", "Vapor"]}`

```json
{
  "s": ["<ul>", "</ul>"],
  "0": {
    "s": ["<li>", "</li>"],
    "d": [["Elixir"], ["Vue"], ["Vapor"]]
  }
}
```

The comprehension shares one `"s"` (statics) across all entries. Each entry in `"d"` is an array of its dynamic values. When an item changes, only that entry's array is re-sent. With `:key`, LiveView tracks identity across reorders.

## Vapor split: what the NIF does

The Rust NIF (`Vize.vapor_split/1`) takes a Vue template string and returns `%{statics, slots}` ready for `%Rendered{}`. All HTML manipulation happens in Rust:

**1. Compile** — runs the Vize Vapor compiler to produce IR (operations, effects, templates)

**2. Parse tag tree** — walks the template HTML tracking open/close tags, building a map from Vapor element IDs to tag byte positions

**3. Inject markers** — for each dynamic slot, inserts a null-byte marker (`\x00`) at the correct position in the HTML:
- `:set_prop` → marker inside the attribute value: `class="\x00"`
- `:set_text` → marker between tags: `<p>\x00</p>`
- structural ops → marker before closing tag of parent

**4. Split** — splits the marked HTML on `\x00` boundaries to produce the statics array

**5. Encode slots** — each slot gets `kind` + expression metadata. Sub-blocks (v-if branches, v-for render block) are recursively split, returned as nested `%{statics, slots}` maps

The result is a plain Elixir map that can be `Macro.escape`d into module bytecode — no NIF call at runtime.

## Expression evaluation

Expressions in slots (e.g. `"count"`, `"user.name"`, `"count > 0 ? 'yes' : 'no'"`) are evaluated at runtime by `PhoenixVapor.Expr`:

```
expression string
      │
      ▼
  OXC.parse/2  (Rust NIF → ESTree AST)
      │
      ▼
  eval_node/2  (pattern match on AST node types)
      │
      ├─ Identifier "count"         → Map.get(assigns, :count)
      ├─ MemberExpression a.b       → nested map access
      ├─ ConditionalExpression      → if/else
      ├─ BinaryExpression + - * /   → arithmetic
      ├─ CallExpression .trim()     → Elixir String/List equivalents
      └─ ArrowFunction, .filter()   → throw :unsupported_node
                                          │
                                          ▼
                                    QuickBEAM.eval/3
                                    (JS runtime in BEAM, optional)
```

The OXC path handles ~90% of real-world template expressions without any JS runtime. QuickBEAM catches the rest.

## Vapor DOM: morphdom bypass

Standard LiveView update path:

```
WebSocket message
      │
      ▼
rendered.mergeDiff(diff)     merge new values into rendered tree
      │
      ▼
rendered.toString()          concatenate statics + dynamics → HTML string
      │
      ▼
document.createElement()     parse HTML string into DOM tree
      │
      ▼
morphdom(container, newDOM)  walk both trees, diff, patch
```

Vapor DOM update path:

```
WebSocket message
      │
      ▼
rendered.mergeDiff(diff)     merge new values into rendered tree
      │
      ▼
registry.get(slotIdx)        look up the DOM node for each changed slot
      │
      ▼
node.textContent = value     one property write per changed slot
node.className = value
```

### How the registry is built

On first render, the client parses the statics array to classify each dynamic slot:

```
statics: ["<div><p class=\"", "\">", "</p></div>"]
                           ↑      ↑
                         slot 0  slot 1
```

- **Slot 0**: prefix ends inside `class="` → attribute slot, key `"class"`
- **Slot 1**: prefix ends with `">` → text content slot

The client walks the live DOM using element paths derived from statics to find the actual DOM nodes, then stores them in a `Map<slotIndex, {type, node, key}>`.

This happens once per unique fingerprint. Subsequent diffs are just map lookups + property writes.

### What uses Vapor DOM vs morphdom fallback

| Scenario | Path |
|---|---|
| Text/attribute-only diff | ✅ Vapor DOM — direct write |
| First render (join) | morphdom — builds initial DOM, then registers nodes |
| Fingerprint change (v-if branch switch) | morphdom — structural change |
| Components (`data-phx-component`) | morphdom — CID routing |
| Streams (`phx-update="stream"`) | morphdom — append/prepend |

## `.vue` SFC → LiveView

`use PhoenixVapor.Reactive, file: "Counter.vue"` compiles at macro expansion time:

```
Counter.vue
    │
    ├─ <template> ──→ Vize.vapor_split/1 ──→ statics/slots (embedded in bytecode)
    │
    └─ <script setup> ──→ OXC.parse/2 ──→ AST
                                │
                                ├─ ref(0)           → mount assign {count: 0}
                                ├─ computed(() => x) → re-evaluated in render
                                ├─ function inc()   → handle_event("inc", ...)
                                └─ defineProps([])   → URL params
```

Generated callbacks:

- **`mount/3`** — initializes assigns from `ref()` initial values
- **`render/1`** — evaluates computeds, then `Renderer.to_rendered(split, assigns)`
- **`handle_event/3`** — one clause per function, executes body in QuickBEAM with current ref state as JS variables, updates assigns with new values, re-evaluates computeds

## Limitations

- No `<slot />` mapping to LiveView inner content
- No `<Suspense>`, `<Transition>`, `<KeepAlive>`
- No watchers or lifecycle hooks (`onMounted`, `watch()`)
- Without QuickBEAM, expressions with callbacks return nil
- SFC `ref()` initial values must be literals; `computed()` must be single-expression arrow functions
- Vapor DOM handles text/attribute diffs only — structural changes (v-if branch switch, v-for reorder) still go through morphdom

## Module inventory

| Module | Lines | Role |
|--------|-------|------|
| `PhoenixVapor` | 64 | Public API, `use` macro |
| `PhoenixVapor.Sigil` | 47 | `~VUE` — compile-time `vapor_split!` |
| `PhoenixVapor.Renderer` | 232 | Slot evaluation → `%Rendered{}` / `%Comprehension{}` |
| `PhoenixVapor.Expr` | 363 | Expression eval — OXC AST + QuickBEAM fallback |
| `PhoenixVapor.Reactive` | 222 | `.vue` SFC → LiveView macro |
| `PhoenixVapor.ScriptSetup` | 171 | `<script setup>` parser via OXC AST |
| `PhoenixVapor.Vue` | 82 | `.vue` → function component with scoped CSS |
| `PhoenixVapor.Component` | 55 | `vue` helper (pass-through) |
| `assets/index.js` | 293 | `patchLiveSocket` — `View.prototype.update` monkey-patch |
| `assets/vapor_patch.js` | 333 | Statics analysis, registry builder, diff applier |

## Dependencies

| Package | What it does here |
|---------|---|
| [Vize](https://hex.pm/packages/vize) | Vue compiler as Rust NIF — `vapor_split/1` |
| [OXC](https://hex.pm/packages/oxc) | JS parser as Rust NIF — expression AST walking |
| [Phoenix LiveView](https://hex.pm/packages/phoenix_live_view) | `%Rendered{}` / `%Comprehension{}` structs |
| [QuickBEAM](https://hex.pm/packages/quickbeam) | Optional — JS runtime for complex expressions and event handlers |
