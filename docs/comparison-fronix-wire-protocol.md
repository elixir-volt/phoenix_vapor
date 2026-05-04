# Wire Protocol Comparison: PhoenixVapor vs Fronix/LiveVue

## Protocol Layers

Both projects share the **same Phoenix LiveView WebSocket transport** (join, heartbeat, events, diffs). The difference is entirely in **what travels inside that transport** and **how the client interprets it**.

---

## PhoenixVapor Wire Protocol

PhoenixVapor uses **LiveView's native rendered diff protocol directly** — no custom encoding layer exists.

### Server → Client Payload

The server produces `%Phoenix.LiveView.Rendered{}` structs, which LiveView serializes as its standard diff format:

```json
// Standard LiveView diff — nothing PhoenixVapor-specific
{
  "0": "active",     // dynamic slot 0: class value
  "1": "Dashboard",  // dynamic slot 1: text content
  "s": ["<div class=\"", "\"><h1>", "</h1></div>"]  // statics (sent once)
}
```

On subsequent updates, **only changed slots are sent**:

```json
{
  "1": "New Title"   // only slot 1 changed
}
```

### Key characteristics

- **No custom wire format** — it's vanilla LiveView diffs
- **Statics sent once** per fingerprint, then cached by client
- **Change tracking** is assign-level: PhoenixVapor's `slot_changed?/2` returns `nil` for unchanged slots, which LiveView omits from the wire
- **Structural nodes** (v-if, v-for) produce nested rendered/comprehension structs that LiveView handles natively
- **Comprehensions** (v-for) use LiveView's built-in keyed list protocol with `has_key?` and entry tuples

### Vapor DOM metadata (optional, out-of-band)

When Vapor DOM patching is enabled, extra metadata is embedded **in the initial HTML** (not in the wire payload):

```html
<div data-vapor data-vapor-statics='["<div class=\"","\"><h1>","</h1></div>"]'>
```

The client uses this to build a **slot→DOM node registry** at mount time. On subsequent diffs, instead of:

```
diff → mergeDiff → toString() → innerHTML → morphdom tree walk
```

It does:

```
diff → mergeDiff → read value from slot index → single DOM write
```

### Wire bandwidth

PhoenixVapor sends **minimal data** — just the changed scalar values. No prop names, no JSON structure, no paths. Slot `"0"` might be a class value, `"1"` a text node. The client already knows the mapping from statics.

---

## Fronix/LiveVue Wire Protocol

Fronix uses **LiveView's hook mechanism** with a **custom data layer on top** of the standard diff protocol.

### Server → Client Payload

The server renders a `<div>` wrapper with **data attributes** containing the component state:

```html
<div
  id="Counter-1"
  data-name="Counter"
  data-props='{"count":5,"items":["a","b"]}'
  data-props-diff='[["test","",7482931]]'
  data-streams-diff='[]'
  data-ssr="true"
  data-use-diff="true"
  data-handlers='{"click":"[[\"push\",{\"event\":\"inc\"}]]"}'
  data-slots='{"default":"PGRpdj5IZWxsbzwvZGl2Pg=="}'
  phx-update="ignore"
  phx-hook="VueHook"
><!-- SSR HTML --></div>
```

### Update cycle

On LiveView re-render, LiveView's diff engine sends the **entire data-attribute strings** as dynamic values. The client hook's `updated()` callback then:

1. Reads `data-props` or `data-props-diff` from the DOM
2. Parses the JSON
3. Applies JSON Patch operations to Vue's reactive props object

### JSON Patch protocol (props diffing)

When `v-diff` is enabled (default), the server computes minimal changes using RFC 6902 JSON Patch with extensions:

```json
[
  ["test", "", 4829173],                    // nonce to force update detection
  ["replace", "/count", 6],                 // simple value change
  ["replace", "/user/name", "New Name"],    // nested path
  ["add", "/items/2", {"id": 3, "text": "new"}]  // array insertion
]
```

Plus custom operations for LiveStreams:

```json
[
  ["test", "", 9283741],
  ["upsert", "/messages/-", {"__dom_id": "msg-5", "text": "hello"}],
  ["remove", "/messages/$$msg-2"],   // $$id syntax for ID-based addressing
  ["limit", "/messages", 50]         // cap array length
]
```

### Slots protocol

HEEX slot content is **base64-encoded** and sent as a data attribute:

```json
{"default": "PGRpdj5IZWxsbzwvZGl2Pg=="}
```

The client decodes and renders it as `innerHTML` inside a wrapper div via Vue's `h()`.

### Event handlers protocol

Server-defined handlers are serialized as LiveView JS command arrays:

```json
{"click": "[[\"push\",{\"event\":\"increment\",\"value\":{}}]]"}
```

The client wraps these into Vue event handlers that call `liveSocket.execJS()`.

---

## Side-by-Side Wire Comparison

Consider a counter component going from `count: 5` to `count: 6`:

### PhoenixVapor over the wire:

```json
{"0": "6"}
```

One key-value pair. 8 bytes of JSON.

### Fronix/LiveVue over the wire:

LiveView sends the re-rendered `<div>` with updated data attributes. The actual diff payload contains the new `data-props-diff` attribute value:

```json
// The data-props-diff attribute value (inside the LiveView diff of the wrapper div)
"[[\"test\",\"\",3847291],[\"replace\",\"/count\",6]]"
```

This is the JSON Patch operation, but it's **double-encoded** (JSON inside an HTML attribute inside a LiveView rendered string diff). The LiveView diff of the wrapper element itself looks like:

```json
{"0": "{\"count\":6}", "1": "[[\"test\",\"\",3847291],[\"replace\",\"/count\",6]]"}
```

~80+ bytes for the same logical update.

---

## Protocol Efficiency Summary

| Metric | PhoenixVapor | Fronix/LiveVue |
|--------|-------------|----------------|
| **Wire format** | Native LiveView slot indices | JSON Patch inside data-attributes inside LiveView diffs |
| **Encoding overhead** | None — direct slot values | Double-encoded (JSON → HTML attr → LV diff) |
| **Prop names on wire** | Never (positional slots) | Always (JSON keys or patch paths) |
| **Statics transmission** | Once per fingerprint | N/A (full props every time unless diff mode) |
| **Structural updates** | Native `%Comprehension{}` keyed diffs | Custom JSON Patch with `upsert`/`limit`/`$$id` |
| **Change detection** | Elixir assign-level (compile-time knowledge of which slot depends on which assign) | Runtime `__changed__` + Jsonpatch.diff |
| **Client DOM update** | Morphdom OR direct slot write (Vapor mode) | Full framework re-render (Vue reactivity absorbs the patch) |
| **Slots** | N/A (rendered natively) | Base64-encoded HTML in data attributes |
| **Events** | Native `phx-click` etc. in rendered HTML | Serialized JS command arrays in `data-handlers` |

---

## Architectural Implications

**PhoenixVapor's protocol advantage**: Because Vue templates are compiled into positional slots at build time, the wire never carries field names, JSON structure, or patch paths. The server knows "slot 3 is the class attribute on the second div" and just sends `{"3": "new-class"}`. The client (in Vapor mode) knows "slot 3 maps to `el.children[1].className`" and writes directly.

**Fronix/LiveVue's protocol advantage**: The JSON Patch approach is **framework-agnostic** and **self-describing**. Any client that understands JSON Patch can consume it. It also supports **partial deep updates** (changing one field in a nested object without resending the whole prop). PhoenixVapor's positional slots don't have a concept of "update one field of a prop object" — the entire slot value is resent.

**The fundamental tradeoff**: PhoenixVapor achieves minimal wire overhead by eliminating the abstraction layer between template and protocol — but this means the client must understand the exact template structure. Fronix accepts larger payloads in exchange for a clean separation where the client only needs to understand "here are your new props."
