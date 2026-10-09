# PhoenixVapor demo

A small issue tracker built with [PhoenixVapor](../../README.md), in the
spirit of Linear: two teams, their boards and issues, kept in memory.
Restarting the server, or "Reset demo" in the sidebar, puts it back.

```sh
mix setup
mix phx.server
```

Then open [localhost:4000](http://localhost:4000). `mix setup` installs the
npm packages from `package.json` and builds the assets.

## The x-ray

Press X, or the X-ray button in the sidebar, to outline every part of the
page by how it renders, and click a part to read its source:

| Outline | How it renders | Where |
| --- | --- | --- |
| Blue | On the server, with no JavaScript: a `~VUE` template or a server-only `.vue` file | the sidebar, the activity rail |
| Green | Hybrid: the server renders the first paint and owns the data; Vue runs it in the browser | the board, the issue page, the list |
| Amber | Folded: a Reka UI component rendered while compiling, once for each value of what it reads | the filter and property menus, the ⌘K palette |
| Violet | Reactive: the `.vue` file's refs and computeds run on the server, in QuickBEAM | the new issue form |

## The pages

All of it is in `lib/vapor_demo_web/`, one folder per page with its LiveView
and its `.vue` file.

- **Board** (`board/Board.vue`, hybrid). The filters and the drag are the
  browser's; a move goes through a `"use server"` function, and every open
  board follows over PubSub. The filter menus are `ui/FilterMenu.vue`, Reka's
  DropdownMenu: their model is a plain string, but the board passes refs typed
  as their values, such as `ref<"all" | "urgent" | "high" | "medium" | "low">`,
  so each menu folds once per value. A `<script lang="elixir">` computes the
  columns for the server's render.
- **Issue** (`issue/Issue.vue`, hybrid). The title and description are edited
  in place and saved through the server; status, priority and assignee are
  `ui/PropertyMenu.vue` menus; comments show at once. The branch name is a
  computed with an Elixir counterpart.
- **Issues and My issues** (`issues/Issues.vue`, hybrid). Grouped by status,
  sorted with a folded menu, and a selection moved at once through one server
  action.
- **New issue** (`new_issue/NewIssue.vue`, Reactive mode). The form's state
  and the branch preview are computed on the server as you type; the value-only
  updates are written straight to the DOM. Creating the issue is the
  LiveView's own Elixir.
- **The ⌘K palette** (`palette/Palette.vue`, hybrid). A LiveView of its own,
  which the root layout renders beside the page, so it stays across
  navigation. Reka's Dialog folds open and closed.
- **The sidebar** (`shell.ex`) is a `~VUE` function component, and the
  **activity rail** (`activity/Activity.vue`) a server-only `.vue` file the
  layout renders as a function component.

The data is `VaporDemo.Tracker`, an Agent seeded by
`VaporDemo.Tracker.Seed` that broadcasts every change. The shared components
are in `assets/js/ui/`: status and priority icons, avatars, the menus, and a
`Button` whose classes come from `variants.ts`, a tailwind-variants macro
evaluated while compiling.

## Session replay

Every page is recorded with [PhoenixReplay](https://hexdocs.pm/phoenix_replay):
use the app, leave the page, and replay the session at
[localhost:4000/dev/replay](http://localhost:4000/dev/replay), a development
route, or from "Replays" in the sidebar. The setup is PhoenixReplay's own:
`PhoenixReplay.Recorder` on the live session in `router.ex`, the dashboard
behind `:dev_routes`, `PhoenixReplay.Plug`, and `replayRecorder(liveSocket)`
in `assets/js/app.ts`.

The hybrid pages need nothing more. While a session is recorded, each reports
the client state its server render reads, and the replay renders with it: the
board follows its filters, as the menus folded once per value show them.

The theme is the server's, as in PhoenixReplay's example app:
`VaporDemoWeb.Theme` keeps it in a cookie, the session and a `@theme` assign,
and the root layout renders it on `<html>`. The dashboard's `frame_layout` is
that root layout, so the replay renders it again at each moment and shows the
theme the session had then.

Each LiveView is a recording of its own: going from the board to an issue
starts another. PhoenixReplay ties a tab's recordings together, and the
player's Visit tab links the one before and after.

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

The test environment sets `data-vapor-debug` on the body, so Reactive mode
counts the updates it writes straight to the DOM, and leaves out the web
fonts, so a page's load doesn't wait on the network.
