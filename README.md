# Phoenix Vapor

Vue template syntax compiled to native `%Phoenix.LiveView.Rendered{}` structs via Rust NIFs. Four progressive modes from zero-JS templates to full hybrid reactivity.

## Modes

| Mode | What | Client JS |
|------|------|-----------|
| `~VUE` sigil | Vue templates in any LiveView | 0 KB |
| `.vue` Reactive | SFC with server-side reactivity (QuickBEAM) | 0 KB |
| `.vue` Hybrid | Split reactivity — server owns data, client owns UI | ~50 KB (Vue 3) |
| Full Vue Runtime | Third-party Vue component libraries server-side | 0 KB |

## `~VUE` Sigil

```elixir
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view
  use PhoenixVapor

  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0)}

  def render(assigns) do
    ~VUE"""
    <div>
      <p>{{ count }}</p>
      <button @click="inc">+</button>
    </div>
    """
  end

  def handle_event("inc", _, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
end
```

Same WebSocket, same diff protocol, same LiveView client. No wrapper divs, no `phx-update="ignore"`.

Supported syntax: `{{ expr }}` · `:attr="expr"` · `@click` · `v-if` / `v-else-if` / `v-else` · `v-for` · `v-show` · `v-model` · `v-html` · ternaries · arithmetic · `.length` · `.toUpperCase()` · dot access · components.

## Reactive Mode

```vue
<script setup>
import { ref, computed } from "vue"
const count = ref(0)
const doubled = computed(() => count * 2)
function increment() { count++ }
</script>

<template>
  <p>{{ count }} × 2 = {{ doubled }}</p>
  <button @click="increment">+</button>
</template>
```

```elixir
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view
  use PhoenixVapor.Reactive, file: "Counter.vue"
end
```

`ref()` → server-side state in QuickBEAM, `computed()` → derived state, functions → event handlers. Three lines of Elixir.

## Hybrid Mode

Server owns data (`defineProps`), client owns UI state (`ref()`). Search, sort, filter are instant — zero server round-trip.

```vue
<script setup>
import { ref, computed } from "vue"
const props = defineProps(["contacts"])
const search = ref("")
const filtered = computed(() =>
  (props.contacts || []).filter(c => c.name.toLowerCase().includes(search.value.toLowerCase()))
)
function deleteContact(id) {
  "use server"
  props.contacts = props.contacts.filter(c => c.id !== id)
}
</script>

<template>
  <input v-model="search" placeholder="Search..." />
  <p>{{ filtered.length }} of {{ props.contacts.length }} contacts</p>
  <div v-for="contact in filtered" :key="contact.id">
    {{ contact.name }}
    <button @click="deleteContact(contact.id)">×</button>
  </div>
</template>
```

```elixir
defmodule MyAppWeb.ContactsLive do
  use MyAppWeb, :live_view
  use PhoenixVapor.Hybrid, file: "Contacts.vue"

  def mount(_params, _session, socket) do
    {:ok, assign(socket, contacts: Repo.all(Contact))}
  end

  def handle_event("deleteContact", %{"id" => id}, socket) do
    Repo.delete!(Contact, id)
    {:noreply, assign(socket, contacts: Repo.all(Contact))}
  end
end
```

The compiler auto-classifies bindings: `defineProps` → server, `ref()` → client, `"use server"` → server action. See [docs/hybrid-architecture.md](docs/hybrid-architecture.md).

## Installation

```elixir
def deps do
  [
    {:phoenix_vapor, "~> 0.2.0"},
    {:quickbeam, "~> 0.10.0", optional: true},
    {:volt, "~> 0.10.0", optional: true}
  ]
end
```

## Toolchain

All compilation runs through Rust NIFs and the BEAM — no Node.js required.

| Tool | Role |
|------|------|
| [Vize](https://hex.pm/packages/vize) | Vue SFC → Vapor IR / standard render functions |
| [OXC](https://hex.pm/packages/oxc) | JS/TS parse, transform, bundle, format, lint |
| [QuickBEAM](https://hex.pm/packages/quickbeam) | Server-side JS runtime (Vue reactivity, complex expressions) |
| [Volt](https://hex.pm/packages/volt) | Dev server, HMR, Tailwind, production builds |

## Docs

- [Architecture](ARCHITECTURE.md) — how each mode works at the protocol level
- [Hybrid Architecture](docs/hybrid-architecture.md) — the split-reactivity design
- [Wire Protocol Comparison](docs/comparisons/fronix-wire-protocol.md) — PhoenixVapor vs Fronix/LiveVue
- [Hologram Comparison](docs/comparisons/hologram.md) — PhoenixVapor vs Hologram
- [examples/demo](examples/demo) — runnable Phoenix app with all modes

## License

MIT
