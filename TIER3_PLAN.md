# Tier 3: Vapor as LiveView's Client-Side Renderer

## Goal

Replace morphdom with Vapor-style direct DOM operations. Instead of serializing
the full HTML string from `%Rendered{}` and letting morphdom diff two DOM trees,
send surgical DOM operation tuples over the wire and apply them directly to
registered node references.

This eliminates innerHTML parsing, tree walking, and heuristic matching on every
update — the client knows exactly which node changed and what to do.

## Architecture

```
Server (current)                    Server (Tier 3)
────────────────                    ────────────────
%Rendered{                          %Rendered{
  static: ["<div>","</div>"],         static: ["<div>","</div>"],
  dynamic: ["42"]                     dynamic: ["42"]     ← unchanged
}                                   }
    │                                   │
    ▼                                   ▼
Diff: {"0": "43"}                   Diff: {"0": "43"}     ← same wire format
    │                                   │
    ▼                                   ▼
Client: rendered.toString()         Client: rendered.applyOps()
    │                                   │
    ▼                                   ▼
"<div>43</div>" (HTML string)       [{op: "text", path: [0], value: "43"}]
    │                                   │
    ▼                                   ▼
morphdom(container, html)           nodeRegistry[0].textContent = "43"
    │                                   │
    ▼                                   ▼
Parse HTML → build DOM tree →       One DOM property write.
walk old + new trees →              Done.
match nodes → apply patches
```

## The Plan: 3 Sub-phases

### Phase 3A: Node Path Registry + Operation Protocol

**Server-side changes: None.** The `%Rendered{}` struct and wire diff format
stay exactly the same. This is a client-only change.

**Client-side: New `VaporPatch` class** (~300 lines)

The insight: LiveView's `%Rendered{}` statics already encode the full template
structure. The dynamic slots are numbered 0, 1, 2, ... and interleave with
statics. We know at first-render time exactly which DOM node each dynamic slot
maps to — because we can parse the static template once and build a registry.

```
statics: ["<div class='", "'>", " items</div>"]
dynamics:    [0]="active"  [1]="42"

Template: <div class='{{0}}'>{{1}} items</div>

Registry:
  slot 0 → attribute "class" on node <div> (root)
  slot 1 → text node (firstChild of root)
```

**VaporPatch workflow:**

1. **First render (join):** Parse statics into a template DOM fragment (same as
   today — innerHTML). But also build a `nodeRegistry`: a map from dynamic slot
   index to `{node, type, key}` where:
   - `type: "text"` → `node.textContent = value`
   - `type: "attr", key: "class"` → `node.setAttribute("class", value)` (or
     className, classList, etc. depending on the key)
   - `type: "prop", key: "value"` → `node.value = value`
   - `type: "html"` → `node.innerHTML = value`
   - `type: "rendered"` → nested %Rendered{} (recursion)
   - `type: "component"` → component CID (existing path)
   - `type: "comprehension"` → list container (special handling)

2. **Subsequent renders (diff):** When a diff arrives with `{"0": "new value"}`,
   look up slot 0 in the registry and apply the operation directly. No toString,
   no morphdom, no HTML parsing.

**How to build the registry from statics:**

The statics array defines the template shape. Between `statics[i]` and
`statics[i+1]` is dynamic slot `i`. By scanning the statics, we can determine
whether each slot is:

- **Inside a tag's attribute value:** `statics[i]` ends inside an opening tag
  (unbalanced `<` without closing `>`). The attribute name is right before `="`.
  → Register as `{type: "attr", key: attrName, node: ...}`

- **Between tags (text content):** `statics[i]` ends with `>` and `statics[i+1]`
  starts with `<` or text. → Register as `{type: "text", node: ...}`

- **An object (nested rendered):** The dynamic value is an object, not a string.
  → Register as `{type: "rendered"}` and handle recursively.

- **A number (component CID):** → Register as `{type: "component"}`

This scanning happens once per unique fingerprint. The result is cached.

**Integration with existing LiveView client:**

```js
// In View.update():
update(diff, events) {
  this.rendered.mergeDiff(diff);

  if (this.vaporEnabled) {
    // New path: apply operations directly
    this.vaporPatch.apply(diff);
  } else {
    // Existing path: toString + morphdom
    const [html, streams] = this.renderContainer(diff, "update");
    const patch = new DOMPatch(this, this.el, this.id, html, streams, null);
    this.performPatch(patch, true);
  }
}
```

**What must still use morphdom (fallback):**

- Join/mount (first render) — morphdom for initial DOM setup, then build registry
- Fingerprint changes — template shape changed, need full re-render + new registry
- Streams — append/prepend/stream operations modify the DOM structure
- `phx-update="ignore"` subtrees
- Components (`data-phx-component`) — need CID routing
- Teleported/portal elements

The Vapor path handles the common case: small diffs on a stable template. The
morphdom path handles structural changes.

**Estimated size:** ~300 lines JS (VaporPatch class + registry builder)

**Risk:** Low. Pure client-side, opt-in, graceful fallback to morphdom.

---

### Phase 3B: Server-Side Operation Encoding

**Server-side: Extend diff protocol** to include operation type hints.

Currently, `%Rendered{}` dynamics are opaque strings or nested structs. The server
doesn't tell the client *what kind* of dynamic each slot is — the client infers it
from the statics context.

Phase 3B makes this explicit. The server annotates each dynamic slot with its
operation type in the diff metadata:

```json
{
  "s": ["<div class='", "'>", " items</div>"],
  "0": "active",
  "1": "42",
  "m": {
    "0": ["a", "class"],
    "1": ["t"]
  }
}
```

Where `"m"` (metadata) maps slot index to operation type:
- `["a", "class"]` — attribute set on "class"
- `["t"]` — text content
- `["h"]` — innerHTML
- `["p", "value"]` — DOM property
- `["r"]` — nested rendered struct
- `["c"]` — component CID

**Why this helps:**

1. Client doesn't need to parse statics to determine operation types — faster
   registry building, less error-prone
2. Server can encode Vapor-specific operations (e.g., `setClass` vs `setAttribute`)
3. Opens the door to operations that don't map to HTML strings at all (style
   objects, event listener changes, etc.)

**Server changes:**

In `LiveVueNext.Renderer`, we already know the operation type for each dynamic
slot (it comes from the Vapor IR: `set_text`, `set_prop`, etc.). We can add this
as metadata to `%Rendered{}`. LiveView's diff engine (`diff.ex`) would need a
small extension to forward this metadata in the wire format.

**Complexity:** Medium. Requires forking `diff.ex` or extending `%Rendered{}` with
a new field. But the change is additive — existing `%Rendered{}` structs without
metadata work as before.

---

### Phase 3C: Full Vapor Runtime on Client

**Client-side: Import Vue Vapor's runtime** for structural operations.

Phase 3A handles text/attribute updates. But structural changes (v-if branch
switch, v-for list update) need more:

- **v-if:** When the condition changes, the server sends a new fingerprint for
  that subtree → tear down old nodes, create new nodes from the new template,
  build new registry for that subtree.

- **v-for:** When the list changes, the server sends comprehension diffs
  (keyed entries with inserts/moves/deletes). Currently this goes through
  morphdom + streams. With Vapor, we can use `createFor`'s LIS algorithm
  to apply minimum DOM moves.

**Import Vapor's key functions:**

```js
import { template, insert, remove } from 'vue/runtime-vapor'
```

Or vendor just the needed functions (~200 lines):
- `template(html)` — create cloneable DOM fragment
- `insert(block, parent, anchor)` — insert nodes
- `remove(block, parent)` — remove nodes
- List reconciliation from `apiCreateFor.ts` — the LIS algorithm

**Comprehension handling:**

```js
// Server sends keyed comprehension diff:
// { "k": { "0": {"0": "Alice"}, "1": {"0": "Bob"}, "kc": 2 }, "s": [...] }

// Instead of rendering to HTML + morphdom:
// 1. Each entry maps to a DOM fragment (template clone)
// 2. Key changes → move/insert/remove fragments
// 3. Value changes → apply operations to fragment's registered nodes
```

This is where the biggest perf win is — list updates go from O(n) morphdom
tree walk to O(changes) direct DOM moves + targeted property writes.

**Complexity:** High. Keyed list reconciliation + fragment lifecycle is where
most edge cases live. But Vapor's implementation is battle-tested.

---

## What Changes Where

### LiveView Client JS (Fork)

| File | Phase | Change |
|------|-------|--------|
| `rendered.js` | 3A | Add `buildRegistry(statics)` method. Cache registries by fingerprint. |
| `rendered.js` | 3B | Read `"m"` metadata from diffs, use for registry building. |
| `view.js` | 3A | Add Vapor update path in `update()`. Fallback to morphdom for structural changes. |
| `dom_patch.js` | 3C | Comprehension reconciliation via Vapor's LIS instead of morphdom + streams. |
| `constants.js` | 3B | Add `METADATA = "m"`, operation type constants. |
| **New:** `vapor_patch.js` | 3A | VaporPatch class: registry builder, operation applier, focus/selection preservation. |

### LiveView Server Elixir (Fork)

| File | Phase | Change |
|------|-------|--------|
| `diff.ex` | 3B | Forward `%Rendered{}` metadata field in diff output. |
| `engine.ex` | 3B | Accept metadata in `%Rendered{}` struct. |
| **OR:** live_vue_next only | 3B | Encode metadata in a way the existing diff engine passes through (e.g., wrap dynamics). |

### live_vue_next

| File | Phase | Change |
|------|-------|--------|
| `renderer.ex` | 3B | Emit operation metadata alongside dynamics. |
| **New:** `assets/vapor_patch.js` | 3A | Client-side Vapor patch engine. |
| **New:** `assets/live_vue_next.js` | 3A | Hook that installs VaporPatch into LiveSocket. |

---

## Key Design Decision: Hijack vs. Fork

Two approaches to integrating with LiveView's client:

### Option A: LiveSocket Hook (No Fork)

Use `dom` callbacks + `phx-hook` to intercept the rendering pipeline:

```js
// In app.js
import { VaporHook } from "live_vue_next"

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { VaporHook },
  dom: {
    onBeforeElUpdated(from, to) {
      // Intercept updates to Vapor-managed elements
      if (from.dataset.vapor) {
        VaporPatch.apply(from, to);
        return false; // skip morphdom for this element
      }
    }
  }
})
```

**Pros:** No LiveView fork. Works with any LiveView version.
**Cons:** Can't intercept at the `rendered.toString()` level — morphdom still
runs, we just skip its output for Vapor elements. Some overhead remains.

### Option B: Fork LiveView Client

Fork `phoenix_live_view` npm package, add Vapor path in `view.js`:

```js
update(diff, events) {
  this.rendered.mergeDiff(diff);

  // Check if this view uses Vapor rendering
  if (this.rendered.hasVaporRegistry()) {
    this.rendered.applyVaporDiff(diff, this.el);
    this.dispatchEvents(events);
    return;
  }

  // Existing morphdom path
  // ...
}
```

**Pros:** Clean integration. No wasted morphdom work. Can optimize the full path
including join, components, comprehensions.
**Cons:** Must maintain a fork. Track upstream changes.

### Recommendation: Start with A, Graduate to B

Phase 3A uses Option A (hook-based, no fork). This validates the approach and
delivers value immediately. If it works well, Phase 3B-3C move to Option B for
the full integration.

---

## Implementation Order

```
Phase 3A: Client-only, no fork                     ~2 days
├── VaporPatch class (registry + applier)           ~200 lines JS
├── Registry builder (parse statics → node map)     ~100 lines JS
├── LiveVueNext hook (installs VaporPatch)           ~50 lines JS
├── Focus/selection preservation                     ~30 lines JS
├── Fallback to morphdom for structural changes      built-in
└── Tests: counter, todo list, showcase              existing demo app

Phase 3B: Server metadata + fork                    ~3 days
├── Extend %Rendered{} with operation metadata       ~50 lines Elixir
├── Forward metadata through diff.ex                 ~30 lines Elixir
├── Client reads metadata for registry               ~50 lines JS
├── Eliminate statics parsing (use metadata)          ~remove 80 lines JS
└── Tests: verify metadata round-trip                 

Phase 3C: Vapor runtime for structural ops           ~5 days
├── Vendor Vapor's template/insert/remove            ~100 lines JS
├── Vendor LIS reconciliation from createFor          ~200 lines JS
├── Comprehension → Vapor list reconciliation        ~150 lines JS
├── v-if → fragment swap with registry rebuild       ~100 lines JS
├── Component CID → Vapor fragment management        ~100 lines JS
├── Edge cases: focus, scroll, transitions            ~100 lines JS
└── Tests: dynamic lists, conditional rendering       

Total: ~1,500 lines new code, ~10 days
```

---

## Proof of Concept: What Phase 3A Looks Like

The simplest version. Given a LiveView that renders:

```elixir
%Rendered{
  static: ["<div><p>Count: ", "</p><p>Doubled: ", "</p></div>"],
  dynamic: fn _ -> [to_string(count), to_string(doubled)] end,
  fingerprint: 12345
}
```

The client builds this registry on first render:

```js
// fingerprint 12345 → registry
{
  0: { type: "text", node: <TextNode "Count: 0">, prefix: "Count: " },
  1: { type: "text", node: <TextNode "Doubled: 0">, prefix: "Doubled: " }
}
```

Wait — that's wrong. The text node content is `Count: 0`, but the dynamic slot
is just `0`. The `Count: ` part is in the statics. So the text node is actually
the *entire content* between static parts. In LiveView's model, the text node
IS the dynamic value — there's no prefix. The statics `</p><p>Doubled: ` is
the separator.

Let me reconsider. LiveView's statics/dynamics produce:

```
static[0] + dynamic[0] + static[1] + dynamic[1] + static[2]
"<div><p>Count: " + "0" + "</p><p>Doubled: " + "0" + "</p></div>"
```

After innerHTML parse, the DOM is:

```
div
├── p
│   ├── "Count: "     ← from static[0] tail
│   └── "0"           ← dynamic[0]
├── p
│   ├── "Doubled: "   ← from static[1] tail  
│   └── "0"           ← dynamic[1]
```

So dynamic[0] maps to: `div > p:first-child > lastChild` (a text node).
And dynamic[1] maps to: `div > p:last-child > lastChild` (a text node).

The registry maps slot indices to text nodes. On update, we just set
`node.textContent = newValue`. No innerHTML, no morphdom.

For attributes it's trickier:

```
static: ["<div class='", "'>...</div>"]
dynamic: ["active"]
```

The `class='` is in static[0], the closing `'` is in static[1]. Dynamic[0]
is the attribute value. We detect this by seeing that static[0] ends inside
an unclosed tag.

**Registry building algorithm:**

```js
function buildRegistry(statics, rootElement) {
  // Walk the statics array. For each boundary between static[i] and static[i+1]:
  // 1. Concatenate statics[0..i] to find current position in template
  // 2. Determine if we're inside a tag (attribute) or between tags (text/html)
  // 3. If attribute: find the attribute name, find the DOM node, register
  // 4. If text: find the text node in the DOM tree, register
}
```

The text node lookup uses the same strategy as Vapor's `children(node, ...paths)`:
count tag boundaries in statics to determine which child we're in, then walk
`firstChild`/`nextSibling` to reach it.

This is the core of Phase 3A. Everything else (focus preservation, fallback to
morphdom) is straightforward.

---

## Risk Analysis

| Risk | Mitigation |
|------|------------|
| Statics parsing is fragile | Phase 3B eliminates it with server metadata |
| Focus/selection preservation | Copy morphdom's approach: save/restore around updates |
| Streams need morphdom | Keep morphdom path for streams (Phase 3A), Vapor for the rest |
| Component CID routing | Keep existing CID component path, Vapor only for leaf content |
| Edge cases in attribute parsing | Use server metadata (3B) before handling edge cases |
| LiveView upstream changes | Hook-based approach (3A) minimizes coupling |

## Success Metrics

- **Latency:** Measure time from WebSocket message to DOM update. Target: 2-5x
  faster than morphdom for text/attribute-only diffs.
- **Memory:** No innerHTML string allocation on updates. Registry is O(dynamics)
  per fingerprint.
- **Compatibility:** All existing LiveView features work — streams, components,
  hooks, JS commands, portals. Vapor path is an optimization, not a replacement.
