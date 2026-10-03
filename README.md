# Phoenix Vapor

[![Hex.pm](https://img.shields.io/hexpm/v/phoenix_vapor.svg)](https://hex.pm/packages/phoenix_vapor) [![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/phoenix_vapor)

Write LiveView templates in Vue syntax, or whole LiveViews as `.vue` files. PhoenixVapor compiles them, through Vue's Vapor-mode IR, to the same `%Phoenix.LiveView.Rendered{}` structs `~H` produces, so they use LiveView's diff protocol and client unchanged.

```elixir
defmodule MyAppWeb.CounterLive do
  use MyAppWeb, :live_view
  use PhoenixVapor

  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0)}

  def render(assigns) do
    ~VUE"""
    <p>{{ count }}</p>
    <button @click="inc">+</button>
    """
  end

  def handle_event("inc", _, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
end
```

## Modes

| Mode | Use | Client JavaScript |
| --- | --- | --- |
| [`~VUE` templates](https://hexdocs.pm/phoenix_vapor/templates.html) | Vue syntax in any LiveView or component | none |
| [Server-only `.vue`](https://hexdocs.pm/phoenix_vapor/templates.html#vue-files) | A `.vue` file as the LiveView's template | none |
| [Reactive](https://hexdocs.pm/phoenix_vapor/reactive.html) | `ref()`, `computed()`, and handlers run on the server in QuickBEAM | none |
| [Hybrid](https://hexdocs.pm/phoenix_vapor/hybrid.html) | The server owns the data, Vue in the browser owns UI state | Vue 3 |
| [Full runtime](https://hexdocs.pm/phoenix_vapor/full-runtime.html) | Vue component libraries such as Reka UI rendered on the server | none |

## Installation

```elixir
def deps do
  [{:phoenix_vapor, "~> 0.3"}]
end
```

Templates need nothing else. Hybrid mode and direct DOM patching need a few lines of browser setup; see [Getting started](https://hexdocs.pm/phoenix_vapor/getting-started.html).

## Documentation

Guides, a cheatsheet, and the API reference are on [HexDocs](https://hexdocs.pm/phoenix_vapor). [`examples/demo`](https://github.com/elixir-volt/phoenix_vapor/tree/master/examples/demo) is a Phoenix app using every mode.

## Part of Elixir Volt

PhoenixVapor compiles Vue templates and single-file components into LiveView, using [Vize](https://github.com/elixir-volt/vize_ex) for Vue, [QuickBEAM](https://github.com/elixir-volt/quickbeam) for server-side JavaScript, and [Volt](https://github.com/elixir-volt/volt) for its browser code.

It is part of a frontend stack that runs inside the BEAM — builds, JS
runtimes, icons, and Vue-to-LiveView compilation as supervised parts of the
application instead of external toolchain processes. See the
[Elixir Volt](https://github.com/elixir-volt) organization for the rest, and
[Building Blocks for the Future Web](https://github.com/elixir-vibe/building-blocks)
for the thesis, architecture, and roadmap that tie them together.

## License

MIT
