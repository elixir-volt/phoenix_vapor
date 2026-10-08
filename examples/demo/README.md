# PhoenixVapor demo

A small workspace app built with [PhoenixVapor](../../README.md), plus a
gallery of its rendering modes. Everything is in memory; restarting the
server resets it.

```sh
mix setup
mix phx.server
```

Then open [localhost:4000](http://localhost:4000). `mix setup` installs the
npm packages from `package.json`, bundles Reka UI for the full runtime page,
and builds the assets.

## The workspace

Two hybrid `.vue` components: Vue runs them in the browser, and the server
renders their first paint and owns their data.

- **Contacts** (`lib/vapor_demo_web/workspace/Contacts.vue`): search,
  sorting, selection and copying an email happen in the browser, with
  es-toolkit's `groupBy` and `sortBy` and VueUse's `refDebounced`,
  `useLocalStorage`, `useClipboard` and `onKeyStroke` (press `/` to search).
  Deleting goes through a `"use server"` function to `VaporDemo.Contacts`,
  which broadcasts the new list to every open page. Its
  `<script lang="elixir">` computes the list in Elixir, since the server
  can't run the composables: the search is a ref, which every render has,
  and the sort order lives in localStorage, so it's read as optional,
  `assigns[:sortKey]`. The first paint sorts by name, and a session replay
  shows the recorded search and order.
- **Settings** (`lib/vapor_demo_web/workspace/ProjectSettings.vue`): Reka UI
  tabs, a select, switches and a dialog, built from the small UI kit in
  `assets/js/ui/`. Renaming the project and removing a member go through
  `VaporDemo.Projects`.

Open either page in two tabs to watch a change in one reach the other.

## The modes

| Page | Mode | Source, in `lib/vapor_demo_web/` |
| --- | --- | --- |
| `/modes/sigil` | `~VUE` in a LiveView, in place of HEEx | `modes/sigil_live.ex` |
| `/modes/server` | A server-only `.vue` file with props | `modes/Team.vue` |
| `/modes/reactive` | A LiveView that is one `.vue` file, its state on the server | `modes/ReactiveCounter.vue` |
| `/modes/hybrid` | Browser state, a server action | `modes/Tally.vue` |
| `/modes/full` | Vue renders a component library on the server | `modes/Dialog.vue` |
| `/modes/compare` | The same template in HEEx and `~VUE` | `modes/compare_live.ex` |

## Layout

```
lib/vapor_demo/                 Contacts and Projects, in-memory contexts with PubSub
lib/vapor_demo_web/workspace/   the app's pages
lib/vapor_demo_web/modes/       the modes gallery
assets/js/app.ts                the LiveSocket, with the hybrid components' hooks
assets/js/ui/                   Button, Badge, Card, Select and Switch
assets/js/bundles/              the Reka UI bundle the full runtime page renders with
assets/js/hybrid/               generated when compiling: the hybrid components' browser halves
```

## Session replay

Every page is recorded with [PhoenixReplay](https://hexdocs.pm/phoenix_replay):
use the app, leave the page, and replay the session at
[localhost:4000/dev/replay](http://localhost:4000/dev/replay), a development
route. The setup is PhoenixReplay's own: `PhoenixReplay.Recorder` on the
`:demo` live session in `router.ex`, the dashboard behind `:dev_routes`,
`PhoenixReplay.Plug`, and `replayRecorder(liveSocket)` in `assets/js/app.ts`.

The hybrid components need nothing more. While a session is recorded, each
reports the client state its server render reads, and the replay renders with
it, so on Contacts the replayed list follows the search, the sort order and
the selection. What it doesn't carry:

- The state of package components rendered while compiling, such as Reka's
  dialog on Contacts and its tabs, select and switches on Settings: the replay
  shows them as they start.
- An optimistic change to a model the server then declined, such as a Tally
  save below zero: the replay shows the server's value throughout.
- The demo's own layout, the navigation and flash messages, which its
  LiveViews apply with the `layout:` option; the replay frame renders the
  view alone.

PhoenixReplay records form controls that have an `id` on its own. The demo's
inputs don't, as their values are refs a component already reports.

## Tests

The tests drive a real browser with Playwright, which `package.json`
includes:

```sh
mix setup
npx playwright install chromium
mix test
```

`mix lint` checks the Elixir, and the TypeScript and the `.vue` components'
scripts with Volt's formatter, linter and type checker; `assets/js/vue.d.ts`
tells TypeScript what importing a `.vue` file gives. `mix ci` runs everything
CI does.

The test environment sets `data-vapor-debug` on the body, so reactive mode
counts the updates it writes straight to the DOM, and the tests check that it
does.
