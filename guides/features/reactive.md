# Reactive Mode

In Reactive mode, a `.vue` file's [`<script setup>`](https://vuejs.org/api/sfc-script-setup.html) runs on the server. Each LiveView gets a QuickBEAM context with [Vue's reactivity system](https://vuejs.org/guide/essentials/reactivity-fundamentals.html) loaded: [`ref()`](https://vuejs.org/api/reactivity-core.html#ref)s hold the state, [`computed()`](https://vuejs.org/guide/essentials/computed.html)s derive from it, and functions handle events. No JavaScript reaches the browser.

```vue
<script setup>
import { ref, computed } from "vue"

const count = ref(0)
const doubled = computed(() => count * 2)

function increment() {
  count++
}
</script>

<template>
  <p>{{ count }} × 2 = {{ doubled }}</p>
  <button @click="increment">+</button>
</template>
```

```elixir
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view
  use PhoenixVapor, file: "Counter.vue", runtime: :reactive
end
```

PhoenixVapor generates `mount/3`, `render/1`, and a `handle_event/3` clause per function.

## How the script is read

Unlike standard Vue, Reactive mode reads refs by name, without `.value`: write `count++` and `count * 2`, not `count.value++`. Each handler runs against copies of the refs, and its results are written back, so Vue's reactivity updates the computeds once per event.

- **Refs**: `const name = ref(initial)`. The initial value is a JavaScript expression.
- **Computeds**: `computed(() => expr)` or `computed(() => { ... return value })`. A computed may read refs and other computeds, in any declaration order.
- **Handlers**: functions declared in `<script setup>`. `@click="increment"` calls `increment`, and the event's params are available as `__params`:

```vue
<script setup>
import { ref } from "vue"
const items = ref([])

function addItem() {
  items.push(__params.value)
}
</script>

<template>
  <form phx-submit="addItem">
    <input name="value" />
  </form>
</template>
```

## Assigns

Refs and computeds become assigns after each event. URL params whose names the template reads are assigned on mount; other params are ignored.

## Direct DOM patching

Reactive-mode renders carry their static HTML in a `data-vapor-statics` attribute. With [`patchLiveSocket`](../introduction/getting-started.md#browser-setup) installed, a diff that only changes values is written straight to the affected text nodes and attributes.

## Runtimes

Each LiveView process owns one JavaScript context, which lives as long as the process. Configure a `QuickBEAM.ContextPool` to share threads between them; see [Getting started](../introduction/getting-started.md#configuration).
