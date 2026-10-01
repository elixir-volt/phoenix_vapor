# Full Runtime

The full runtime renders a `.vue` component on the server with the complete Vue runtime in QuickBEAM: `provide`/`inject`, slots, composition, and third-party component libraries such as [Reka UI](https://reka-ui.com). The rendered HTML is sent through LiveView, and events go back to the component's handlers, so the browser runs no Vue.

```elixir
defmodule MyAppWeb.DialogLive do
  use MyAppWeb, :live_view

  use PhoenixVapor,
    file: "Dialog.vue",
    runtime: :full,
    bundle: "priv/js/reka-dialog.js",
    globals: %{"reka-ui" => "RekaDialog"}
end
```

## Bundling dependencies

The component's imports resolve against a bundle that defines them as globals: Vue as `Vue`, and each library under the name you give in `:globals`. Build one with `mix phoenix_vapor.bundle` from an entry file:

```js
// assets/reka-entry.js
import * as Vue from "vue"
import * as RekaUI from "reka-ui"

globalThis.Vue = Vue
globalThis.RekaDialog = RekaUI
```

```bash
mix npm.install vue reka-ui
mix phoenix_vapor.bundle --entry assets/reka-entry.js --name reka-dialog
```

The task writes `priv/js/reka-dialog.js` with Volt. Options: `--entry`, `--outdir` (default `priv/js`), `--name`, and `--minify`/`--no-minify`.

## Options

- `:bundle`: path to the bundle. It is read once and cached until the file changes.
- `:globals`: a map from each imported package to its global in the bundle. `vue` is always `Vue`.

## Lifecycle

PhoenixVapor generates `mount/3`, `render/1`, `handle_event/3`, and `terminate/2`. They are overridable; call `super` to keep the runtime:

```elixir
def mount(params, session, socket) do
  {:ok, socket} = super(params, session, socket)
  {:ok, assign(socket, :account, load_account(session))}
end

def handle_event("host-event", params, socket) do
  {:noreply, handle_host_event(params, socket)}
end

def handle_event(event, params, socket), do: super(event, params, socket)
```

A JavaScript exception in the component raises in the LiveView process as a `QuickBEAM.JSError`.
