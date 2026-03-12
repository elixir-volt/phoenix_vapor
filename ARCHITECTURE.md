# Architecture

## Three rendering systems compared

Phoenix Vapor sits at the intersection of two rendering architectures that independently arrived at the same patterns. This section compares them at the protocol and DOM operation level, then shows how Phoenix Vapor bridges them.

### The template: a counter

```html
<div>
  <p class="active">Count: 42</p>
  <button>+</button>
</div>
```

### How Phoenix LiveView renders it

**Compile time** — the HEEx engine splits the template into static strings and dynamic holes:

```elixir
# ~H"""
# <div>
#   <p class={@label}>Count: <%= @count %></p>
#   <button phx-click="inc">+</button>
# </div>
# """

%Rendered{
  static: ["<div><p class=\"", "\">Count: ", "</p><button phx-click=\"inc\">+</button></div>"],
  dynamic: fn changed? ->
    [
      if !changed? || changed?[:label], do: assigns.label,   # slot 0
      if !changed? || changed?[:count], do: assigns.count    # slot 1
    ]
  end,
  fingerprint: 28537016426557327042948424934498587137
}
```

**Wire — first render (join reply):**

```json
{
  "s": ["<div><p class=\"", "\">Count: ", "</p><button phx-click=\"inc\">+</button></div>"],
  "0": "active",
  "1": "42"
}
```

Key `"s"` = statics (sent once, cached by fingerprint). `"0"`, `"1"` = dynamic slot values.

**Wire — update (only count changed):**

The server sees `__changed__: %{count: true}`. Slot 0 (label) returns `nil` → omitted. Only slot 1 is sent:

```json
{"1": "43"}
```

**Client processing (`rendered.js` → `dom_patch.js`):**

```
1. rendered.mergeDiff({"1": "43"})
   └─ stores "43" at rendered["1"]

2. rendered.toString()
   └─ concatenates: static[0] + rendered[0] + static[1] + rendered[1] + static[2]
   └─ result: "<div><p class=\"active\">Count: 43</p><button phx-click=\"inc\">+</button></div>"

3. new DOMPatch(view, container, id, html, streams, null)
   └─ wraps in container tag: "<div id=\"phx-Fxyz\"><div><p class=...>...</div></div>"

4. morphdom(targetContainer, source, callbacks)
   └─ parses source HTML into a DOM tree
   └─ walks both old and new trees node by node
   └─ for each node pair: compares tag, attributes, children
   └─ applies minimal mutations: here just textContent of one text node
   └─ runs ~30 callback hooks (onBeforeElUpdated, onNodeAdded, onNodeDiscarded, ...)
   └─ handles focus preservation, form state, PHX_SKIP optimization, streams, etc.
```

For a single number change, morphdom still: allocates an HTML string, parses it into DOM, walks the entire tree, and compares every node.

### How Vue Vapor renders it

**Compile time** — the Vapor compiler produces JS code that creates a template once and sets up per-expression reactive effects:

```js
const t0 = _template("<div><p><button>+</button></p></div>")

export function render(_ctx) {
  const n0 = t0()                          // cloneNode(true) from cached template
  const n1 = n0.firstChild                 // <p>
  const n2 = n1.nextSibling               // <button>

  // One effect per dynamic expression, tracked by Vue's reactivity system
  renderEffect(() => setClass(n1, _ctx.label))
  renderEffect(() => setText(n1, "Count: ", _ctx.count))
  on(n2, "click", _ctx.inc)

  return n0
}
```

**Runtime — update (count changes from ref(42) to ref(43)):**

```
1. Vue's reactivity system detects that `count` ref changed
2. Only the setText effect is dirty (setClass effect's deps didn't change)
3. The scheduler runs: setText(n1, "Count: ", 43)
   └─ n1.textContent = "Count: 43"    ← one DOM write
```

No wire protocol — everything happens client-side. No HTML string. No tree diff. The reactive dependency graph knows exactly which effects to re-run.

### How Phoenix Vapor bridges them

**Compile time** — Vize (Rust NIF) compiles the Vue template to a statics/slots split:

```elixir
Vize.vapor_split!(~s[<div><p :class="label">Count: {{ count }}</p><button @click="inc">+</button></div>])

%{
  statics: ["<div><p class=\"", "\">", "</p><button phx-click=\"inc\">+</button></div>"],
  slots: [
    %{kind: :set_prop, values: ["label"]},              # slot 0 — attribute
    %{kind: :set_text, values: [{:static_, "Count: "}, "count"]}  # slot 1 — text
  ]
}
```

`@click="inc"` becomes `phx-click="inc"` in statics. `:class="label"` becomes a `set_prop` slot.

**Runtime** — `Renderer.to_rendered/2` evaluates slots against LiveView assigns:

```elixir
%Rendered{
  static: ["<div><p class=\"", "\">", "</p><button phx-click=\"inc\">+</button></div>"],
  dynamic: fn changed? ->
    [
      if !changed? || slot_changed?(:label, changed?), do: "active",
      if !changed? || slot_changed?(:count, changed?), do: "Count: 42"
    ]
  end,
  fingerprint: 94949380559044124300359658668089091771
}
```

From here it's standard LiveView. Same `diff.ex`, same wire format, same `"s"`/`"0"`/`"1"` keys.

**Wire — identical to LiveView:**

```json
{"1": "Count: 43"}
```

**Client — with `patchLiveSocket` (Vapor DOM):**

```
1. rendered.mergeDiff({"1": "Count: 43"})
   └─ same as standard LiveView

2. Instead of toString + morphdom:
   └─ registry lookup: slot 1 → {type: "text", node: <TextNode>}
   └─ node.textContent = "Count: 43"     ← one DOM write, like Vue Vapor
```

The registry is built once on first render by parsing the statics:

```
statics: ["<div><p class=\"", "\">", "</p>..."]
                            ↑      ↑
                          slot 0  slot 1

slot 0: prefix ends inside class=" → type: "attr", key: "class", node: <p>
slot 1: prefix ends with ">       → type: "text", node: <p>.childNodes[1]
```

### Summary

|  | LiveView (HEEx) | Vue Vapor | Phoenix Vapor |
|--|---|---|---|
| **Template syntax** | `<%= @count %>` | `{{ count }}` | `{{ count }}` (Vue) |
| **Compilation** | Elixir AST | JS codegen | Rust NIF → statics/slots |
| **Server state** | `assigns` map | — (client only) | `assigns` map |
| **Change tracking** | `__changed__` map | Reactive dep graph | `__changed__` map |
| **Wire format** | `{"s": [...], "0": "val"}` | — (no wire) | Same as LiveView |
| **Client: first render** | innerHTML + morphdom | template() + cloneNode | innerHTML + morphdom + build registry |
| **Client: update** | toString → innerHTML → morphdom | setText(node, val) | registry[slot].node.textContent = val |
| **Structural change** | New fingerprint → full re-render | Tear down + mount new block | New fingerprint → morphdom fallback |
| **List reconciliation** | `%Comprehension{}` + keyed | createFor + LIS algorithm | `%Comprehension{}` + keyed |

---

## LiveView wire protocol reference

The keys used in the JSON diff protocol, as defined in `constants.js` and `diff.ex`:

| Key | Constant | Meaning |
|-----|----------|---------|
| `"s"` | `STATIC` | Statics array — the unchanging HTML fragments. Sent on first render or fingerprint change. Can be an integer referencing a shared template. |
| `"0"`, `"1"`, ... | (integer keys) | Dynamic slot values. String = text/attribute value. Object = nested `%Rendered{}`. Integer = component CID. `null` = unchanged. |
| `"r"` | `ROOT` | `1` if this rendered struct is a root element (has a single static HTML tag at the top). |
| `"c"` | `COMPONENTS` | Map of component CID → component diff. Components are diffed separately and referenced by integer CID in the parent's dynamic slots. |
| `"p"` | `TEMPLATES` | Shared template registry. Map of integer index → statics array. Multiple rendered structs with the same fingerprint share statics via integer reference in `"s"`. |
| `"k"` | `KEYED` | Keyed comprehension entries. Map of index → entry diff. Entries can be: object (new/changed), integer (moved, no changes), `[old_idx, diff]` (moved with changes). |
| `"kc"` | `KEYED_COUNT` | Total number of entries in the comprehension. |
| `"stream"` | `STREAM` | Stream metadata: `[ref, inserts, deleteIds, reset]`. |
| `"e"` | `EVENTS` | Server-pushed events. |
| `"t"` | `TITLE` | Page title update. |
| `"r"` | `REPLY` | Reply payload for `handle_event` return. |

### Nested rendered struct (v-if)

A dynamic slot containing an object is a nested `%Rendered{}`:

```json
{
  "s": ["<div>", "</div>"],
  "0": {
    "s": ["<p>", "</p>"],
    "0": "Hello",
    "r": 1
  }
}
```

When the fingerprint changes (v-if branch switch), the new `"s"` is sent:

```json
{
  "0": {
    "s": ["<p>Hidden</p>"]
  }
}
```

The client sees new statics → discards the old subtree and renders fresh.

### Comprehension (v-for)

```json
{
  "s": ["<ul>", "</ul>"],
  "0": {
    "s": ["<li>", "</li>"],
    "k": {
      "0": {"0": "Elixir"},
      "1": {"0": "Vue"},
      "2": {"0": "Vapor"},
      "kc": 3
    }
  }
}
```

On update (item 1 changed, item 2 moved):

```json
{
  "0": {
    "k": {
      "1": {"0": "Vue 4"},
      "2": 1,
      "kc": 3
    }
  }
}
```

- `"1": {"0": "Vue 4"}` — entry at index 1 has new dynamics
- `"2": 1` — entry at index 2 was previously at index 1 (moved, no content change)
- `"kc": 3` — still 3 entries total

### Component CID

Dynamic slot containing an integer = component CID reference:

```json
{
  "s": ["<div>", "</div>"],
  "0": 1,
  "c": {
    "1": {
      "s": ["<span>", "</span>"],
      "0": "component content"
    }
  }
}
```

Component diffs are in `"c"`, keyed by CID. Static sharing across components uses negative CID: `"s": -3` means "use statics from CID 3".

### Template sharing (`"p"` key)

When multiple structures share the same statics (same fingerprint), the server sends statics once in `"p"` and references by integer:

```json
{
  "p": {
    "0": ["<li>", "</li>"]
  },
  "s": ["<ul>", "</ul>"],
  "0": {
    "s": 0,
    "k": { "0": {"0": "a"}, "1": {"0": "b"}, "kc": 2 }
  }
}
```

`"s": 0` means "look up statics at `templates[0]`" → `["<li>", "</li>"]`.

### Client processing pipeline

```
WebSocket message
      │
      ▼
Rendered.extract(diff)
├─ pulls out "e" (events), "t" (title), "r" (reply)
└─ returns {diff, title, reply, events}
      │
      ▼
rendered.mergeDiff(diff)
├─ if diff has "s" → new fingerprint, replace entire subtree state
├─ if diff has "k" → keyed comprehension merge:
│   ├─ integer entry → moved without changes
│   ├─ [old_idx, diff] → moved with changes
│   └─ object entry → new or in-place update
├─ otherwise → merge dynamic values by key
└─ sets newRender flag on root elements
      │
      ▼
rendered.toString(cids)
├─ recursiveToString walks the rendered tree
├─ concatenates: static[0] + dynamic[0] + static[1] + dynamic[1] + ...
├─ integers in dynamic slots → recursiveCIDToString (component rendering)
├─ objects in dynamic slots → recursive toOutputBuffer
├─ comprehensions → comprehensionToBuffer (loops over keyed entries)
├─ root elements get data-phx-id="m{N}" for skip optimization
└─ if !newRender → data-phx-skip="true" (morphdom skips innerHTML)
      │
      ▼
new DOMPatch(view, container, id, html, streams)
      │
      ▼
morphdom(targetContainer, source, callbacks)
├─ parses source HTML string into DOM tree
├─ getNodeKey: uses element id or data-phx-id for matching
├─ onBeforeElUpdated:
│   ├─ data-phx-skip → return false (skip this subtree entirely)
│   ├─ PHX_REF_LOCK → clone tree for pending form lock
│   ├─ focused form input → mergeFocusedInput (preserve user input)
│   ├─ phx-update="ignore" → merge attrs only
│   └─ otherwise → allow morphdom to patch
├─ onNodeAdded: handles streams, portals, nested views, runtime hooks
├─ onNodeDiscarded: destroys child views, hooks
└─ after morph: restore focus/selection, dispatch "phx:update"
```

---

## Phoenix Vapor: how the bridge works

### Compile-time pipeline

```
Vue template ─→ Vize.vapor_split/1 ─→ %{statics, slots}
                    Rust NIF
```

The NIF performs 5 steps in Rust:

1. **Compile** — Vize Vapor compiler produces IR (operations, effects, templates)
2. **Parse tag tree** — walks HTML tracking open/close tags, maps Vapor element IDs to byte positions
3. **Inject markers** — inserts `\x00` at split points: inside attribute values for `:attr`, between tags for `{{ text }}`, before closing tags for structural directives
4. **Split** — splits on `\x00` boundaries → statics array
5. **Encode slots** — each slot gets `kind` + expression metadata. Sub-blocks (v-if branches, v-for body) are recursively split

Result is `Macro.escape`d into BEAM bytecode — no NIF at runtime.

### Runtime evaluation

```elixir
Renderer.to_rendered(split, assigns)
```

For each slot in order:

1. Check `__changed__` — if no referenced assigns changed, return `nil` (LiveView skips in diff)
2. Evaluate expression via `Expr.eval`:
   - `:set_text` → concatenate values, HTML-escape → string
   - `:set_prop` → concatenate values, HTML-escape → string
   - `:set_html` → evaluate, no escaping → string
   - `:v_show` → evaluate condition → `""` or `"display: none"`
   - `:v_model` → evaluate, HTML-escape → string
   - `:if_node` → evaluate condition, recurse into positive or negative branch → nested `%Rendered{}`
   - `:for_node` → evaluate source list, render each item → `%Comprehension{}`
   - `:create_component` → look up in `__components__`, call with props → rendered output

Output: standard `%Rendered{}` that `diff.ex` processes without modification.

### Vapor DOM client

With `patchLiveSocket(liveSocket)`, the client monkey-patches `View.prototype.update`:

```
diff arrives
      │
      ├─ has "c" (components) or "s" (new statics)?
      │   yes → fall back to standard toString + morphdom
      │
      ├─ find [data-vapor-statics] element in view
      │   not found → fall back
      │
      ├─ registry exists?
      │   no → fall back
      │
      └─ for each changed slot in diff:
          registry.get(slotIdx)
          ├─ type: "text" → node.nodeValue = value
          └─ type: "attr" → el.className / el.setAttribute / el.style.cssText = value
```

Registry is built once per element from `data-vapor-statics` (JSON-encoded statics array):

```js
analyzeStatics(["<div><p class=\"", "\">", "</p></div>"])
// → [
//   {type: "attr", nodePath: [0], key: "class"},
//   {type: "text", parentPath: [0], textIndex: 0}
// ]

resolveRegistry(slots, rootElement)
// → Map {
//   0 → {type: "attr", node: <p>, key: "class"},
//   1 → {type: "text", node: #text}
// }
```

---

## `.vue` SFC → LiveView

`use PhoenixVapor.Reactive, file: "Counter.vue"` at macro expansion:

```
Counter.vue
    │
    ├─ <template> ──→ Vize.vapor_split/1 ──→ statics/slots (embedded in bytecode)
    │
    └─ <script setup> ──→ OXC.parse/2 ──→ AST
                                │
                                ├─ ref(0)            → mount assign {count: 0}
                                ├─ computed(() => x) → re-evaluated in render
                                ├─ function inc()    → handle_event("inc", ...)
                                └─ defineProps([])   → URL params merged to assigns
```

Generated callbacks:

- **`mount/3`** — initializes assigns from `ref()` initial values
- **`render/1`** — evaluates computeds, then `Renderer.to_rendered(split, assigns)`
- **`handle_event/3`** — one clause per function, executes body in QuickBEAM against current state, updates assigns, re-evaluates computeds

## Expression evaluation

```
expression string
      │
      ▼
  OXC.parse/2  (Rust NIF → ESTree AST)
      │
      ▼
  eval_node/2  (Elixir pattern match on AST node types)
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

## Limitations

- No `<slot />` mapping to LiveView inner content
- No `<Suspense>`, `<Transition>`, `<KeepAlive>`
- No watchers or lifecycle hooks (`onMounted`, `watch()`)
- Without QuickBEAM, expressions with callbacks return nil
- SFC `ref()` initial values must be literals; `computed()` must be single-expression arrow functions
- Vapor DOM handles text/attribute diffs only — structural changes fall back to morphdom

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
