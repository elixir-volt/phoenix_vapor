# Getting Started

## Installation

```elixir
def deps do
  [{:phoenix_vapor, "~> 0.6"}]
end
```

PhoenixVapor brings [Vize](https://hex.pm/packages/vize), which compiles Vue, and [QuickBEAM](https://hex.pm/packages/quickbeam), which runs JavaScript on the server: for Reactive mode and the full runtime, for macros and package components while compiling, and for the few expressions only JavaScript can evaluate. [Volt](https://hex.pm/packages/volt) compiles PhoenixVapor's own TypeScript at build time. All of them are precompiled NIFs, so there is no Node.js to install.

## Choosing a mode

Start with the simplest mode that does what you need:

1. **[`~VUE` templates](../features/templates.md)**: [Vue syntax](https://vuejs.org/guide/essentials/template-syntax.html) in place of HEEx. Assigns, events, and state stay ordinary LiveView.
2. **[Server-only `.vue` files](../features/templates.md#vue-files)**: the same, with the template in a [single-file component](https://vuejs.org/guide/scaling-up/sfc.html).
3. **[Reactive](../features/reactive.md)**: a `.vue` file whose `ref()` state, computeds, and handlers run on the server. The LiveView module can be empty.
4. **[Hybrid](../features/hybrid.md)**: the server owns the data passed as props, and Vue in the browser owns UI state. Interactions such as filtering and sorting never reach the server.
5. **[Full runtime](../features/full-runtime.md)**: render Vue component libraries on the server with the complete Vue runtime.

`use PhoenixVapor, file: "X.vue"` picks the mode from the file: a [`<script setup>`](https://vuejs.org/api/sfc-script-setup.html) with `ref()` is hybrid, anything else is server-only. Pass `runtime: :reactive` or `runtime: :full` to choose those.

## Browser setup

Templates and server-only `.vue` files need no browser changes. Hybrid components, and direct DOM patching for Reactive mode, use modules PhoenixVapor ships as TypeScript. With Volt, resolve them from `deps`:

```elixir
# config/config.exs
config :volt,
  resolve_dirs: ["node_modules", "deps"]
```

For a path or umbrella dependency, which isn't under `deps/`, add `plugins: [PhoenixVapor.Volt]` instead; it resolves the imports from wherever Mix put PhoenixVapor.

Then, in `assets/js/app.js`:

```js
import { patchLiveSocket } from "phoenix_vapor"
import { getHybridHooks } from "phoenix_vapor/hybrid"
import * as Contacts from "./hybrid/Contacts.hybrid.js"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...getHybridHooks({ Contacts }) }
})

patchLiveSocket(liveSocket)
liveSocket.connect()
```

- `getHybridHooks` registers the `PhoenixVaporHybrid` hook for the hybrid components you pass. Each hybrid LiveView compiles its component to `assets/js/hybrid/<Name>.hybrid.js`.
- `patchLiveSocket` writes value-only diffs for Reactive-mode renders straight to the DOM, skipping LiveView's re-render and morphdom pass. It is optional.

The hybrid client is a standard Vue 3 component, so install `vue` (3.5 or later) in your assets (`mix npm.install vue`).

## Configuration

Reactive mode and the full runtime start a QuickBEAM runtime per LiveView. In production, share a pool of lightweight contexts instead:

```elixir
# In your application's supervision tree
{QuickBEAM.ContextPool, name: MyApp.JSPool, size: 4}

# config/config.exs
config :phoenix_vapor, pool: MyApp.JSPool
```

## Example app

[`examples/demo`](https://github.com/elixir-volt/phoenix_vapor/tree/master/examples/demo) is a small issue tracker built with PhoenixVapor: a `~VUE` shell, server-only `.vue` components, a Reactive-mode form, and hybrid pages with Reka UI menus and dialogs folded at compile time. Its x-ray, the X key, outlines how each part of a page renders.
