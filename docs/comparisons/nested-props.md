# Nested Props: Wire Protocol Comparison

How PhoenixVapor and Fronix/LiveVue handle nested and deeply nested prop updates on the wire.

---

## The Scenario

Consider this data structure:

```elixir
assigns = %{
  user: %{
    name: "Alice",
    address: %{
      city: "Moscow",
      zip: "101000"
    },
    tags: ["admin", "active"]
  }
}
```

Now only `user.address.city` changes to `"Berlin"`.

---

## PhoenixVapor

PhoenixVapor's change tracking operates at the **root assign level**. The `assign_keys/1` function extracts only the root identifier:

```elixir
# For expression "user.address.city", assign_keys returns:
[:user]
```

So when `user` is marked as changed in `__changed__`, **every slot that references `user` in any way is re-evaluated and re-sent**:

```vue
<div>
  <h1>{{ user.name }}</h1>           <!-- slot 0: re-sent even though name didn't change -->
  <p>{{ user.address.city }}</p>     <!-- slot 1: re-sent (actually changed) -->
  <p>{{ user.address.zip }}</p>      <!-- slot 2: re-sent even though zip didn't change -->
  <span>{{ user.tags.length }}</span> <!-- slot 3: re-sent even though tags didn't change -->
</div>
```

Wire payload:

```json
{
  "0": "Alice",
  "1": "Berlin",
  "2": "101000",
  "3": "3"
}
```

All four slots resent. ~40 bytes. No structural overhead, but **no sub-key granularity** — changing any nested field resends every expression touching that root assign.

### What if the template only uses the leaf?

```vue
<p>{{ user.address.city }}</p>
```

Wire:

```json
{"0": "Berlin"}
```

Still minimal — 14 bytes. But the slot is triggered by *any* change to `user`, not just `address.city`.

---

## Fronix/LiveVue

LiveVue's change tracking is **two-tiered**:

1. **LiveView level**: `__changed__` tracks which root assigns changed, but for complex values it stores the **old value** (not just `true`)
2. **JSON Patch level**: `Jsonpatch.diff(old_value, new_value)` computes the minimal structural difference

For the same scenario, the server computes:

```elixir
# __changed__ contains the OLD user map
# Jsonpatch.diff compares old vs new, producing:
[%{op: "replace", path: "/user/address/city", value: "Berlin"}]
```

Wire payload (inside `data-props-diff` attribute):

```json
[["test","",7391824],["replace","/user/address/city","Berlin"]]
```

~60 bytes. More structural overhead, but **only the changed leaf is transmitted** — `name`, `zip`, and `tags` are never mentioned.

---

## Deep Nesting Scaling

Consider a 3-level deep object with 20 leaf fields, where 1 leaf changes:

| | PhoenixVapor | Fronix/LiveVue |
|---|---|---|
| **Slots resent** | All slots referencing the root assign (could be 20) | 0 — patch targets the single leaf |
| **Wire size** | Proportional to # of template usages of that assign | Constant — one patch op regardless of object size |
| **Example** | `{"0":"v1","1":"v2",...,"19":"v20"}` | `[["test","",N],["replace","/a/b/c","v3"]]` |

### The opposite: all 20 fields change

| | PhoenixVapor | Fronix/LiveVue |
|---|---|---|
| **Wire size** | Same — 20 slot values, no keys needed beyond indices | 20 replace ops, each with full path |
| **Example** | `{"0":"v1","1":"v2",...,"19":"v20"}` (~compact) | `[["test","",N],["replace","/a","v1"],["replace","/b","v2"],...]` (~verbose) |

PhoenixVapor wins when many fields change simultaneously because its format has no per-field path overhead.

---

## Array/List Updates

Consider `items` is a list of 1000 objects. One item at index 500 changes its `status` field.

### PhoenixVapor (v-for)

The `v-for` produces a `%Comprehension{}`. LiveView's keyed comprehension protocol can diff entries by key. But PhoenixVapor re-evaluates the entire `for_node` slot when `items` is in `__changed__`:

```json
// Comprehension diff: LiveView sends only the changed entry
// but the ENTIRE entry's slots are re-rendered
{"d": [["item-500", {"0": "shipped", "1": "Order #500"}]]}
```

The keyed comprehension avoids resending all 1000 entries — only the changed key is transmitted. But within that entry, all dynamic slots are re-evaluated.

### Fronix/LiveVue (streams)

```json
[["test","",N],["replace","/items/$$item-500/status","shipped"]]
```

Single-field precision even within list items, using the `$$id` addressing syntax. No other fields of item-500 are resent.

### Fronix/LiveVue (without streams, full prop)

If using plain props (no LiveStream), the entire `items` array is re-encoded and re-diffed:

```json
[["test","",N],["replace","/items/500/status","shipped"]]
```

Still targets just the leaf, but computing `Jsonpatch.diff` on 1000 items is expensive server-side.

---

## Summary Table

| Scenario | PhoenixVapor | Fronix/LiveVue |
|----------|-------------|----------------|
| **1 leaf of deep object changes** | Resends ALL slots referencing that root assign | Sends 1 patch op targeting the exact path |
| **All fields change** | Compact positional slots, no paths | Verbose — N patch ops with full paths |
| **1 item in large list changes** | Keyed comprehension: resends that entry's slots | Stream patch: targets single field in single item |
| **Granularity** | Root assign level (coarse) | JSON path level (fine) |
| **Overhead per update** | Zero structural overhead | Path strings + op names per change |
| **Server-side cost** | Cheap — just eval changed slots | Expensive — `Jsonpatch.diff` over entire structure |
| **Template coupling** | Resend depends on what the template uses | Resend depends only on what changed in data |

---

## The Core Tradeoff

**PhoenixVapor** is **template-aware but data-naive**: it knows which assign a slot depends on, but treats the assign as an opaque blob. A single field change in a deeply nested object triggers resending of every slot that touches any part of that object.

**Fronix/LiveVue** is **data-aware but template-naive**: it doesn't know how the frontend uses the data, but it computes the minimal structural diff of the data itself. Only the exact changed paths are transmitted, regardless of how many template locations consume them.
