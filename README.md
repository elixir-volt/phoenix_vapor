# Phoenix Vapor

Vue template syntax compiled to native `%Phoenix.LiveView.Rendered{}` structs via Rust NIFs.

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

## Three tiers

| Tier | What | How |
|------|------|-----|
| `~VUE` sigil | Vue templates in any LiveView | `~VUE"""<p>{{ count }}</p>"""` |
| `.vue` SFC | Complete LiveView from a `.vue` file | `use PhoenixVapor.Reactive, file: "Counter.vue"` |
| Vapor DOM | Bypass morphdom — direct DOM writes | `patchLiveSocket(liveSocket)` |

## Installation

```elixir
def deps do
  [
    {:phoenix_vapor, "~> 0.1.0"},
    {:quickbeam, "~> 0.3.0", optional: true}  # for complex JS expressions
  ]
end
```

## Supported syntax

`{{ expr }}` · `:attr="expr"` · `@click="handler"` · `v-if` / `v-else-if` / `v-else` · `v-for` · `v-show` · `v-model` · `v-html` · ternaries · arithmetic · `.length` · `.toUpperCase()` · dot access · components

Simple expressions evaluate in pure Elixir via OXC AST. Complex expressions (arrow functions, `.filter()`, `.map()`) fall back to [QuickBEAM](https://hex.pm/packages/quickbeam).

## `.vue` SFC mode

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

`ref()` → assigns, `computed()` → derived state, functions → event handlers. Three lines of Elixir.

## Vapor DOM

Opt-in morphdom bypass. The client parses statics once, builds a registry mapping each dynamic slot to its DOM node, then applies diffs as direct property writes.

```js
import { patchLiveSocket } from "phoenix_vapor"
patchLiveSocket(liveSocket)
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for protocol-level details.

## Docs

- **[ARCHITECTURE.md](ARCHITECTURE.md)** — how it works at the protocol level, with wire format examples
- **[examples/demo/](examples/demo/)** — runnable Phoenix app with all features

## License

MIT
