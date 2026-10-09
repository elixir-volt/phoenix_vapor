# Hybrid Mode

Hybrid mode splits a `.vue` component between the server and the browser. The server owns the data, passed in as props and models, and Vue in the browser owns UI state. Searching, sorting, and selecting happen in the browser without a round trip; changes to the data go through server actions over the LiveView socket.

```vue
<script setup>
import { ref, computed } from "vue"

const contacts = defineModel("contacts")
const search = ref("")

const filtered = computed(() =>
  contacts.value.filter(c => c.name.toLowerCase().includes(search.value.toLowerCase()))
)

function deleteContact(id) {
  "use server"
  contacts.value = contacts.value.filter(c => c.id !== id)
}
</script>

<template>
  <input v-model="search" placeholder="Search..." />
  <p>{{ filtered.length }} of {{ contacts.length }} contacts</p>
  <div v-for="contact in filtered" :key="contact.id">
    {{ contact.name }}
    <button @click="deleteContact(contact.id)">×</button>
  </div>
</template>
```

```elixir
defmodule MyAppWeb.ContactsLive do
  use MyAppWeb, :live_view
  use PhoenixVapor, file: "Contacts.vue"

  def mount(_params, _session, socket) do
    {:ok, assign(socket, contacts: Repo.all(Contact))}
  end

  def handle_event("deleteContact", %{"id" => id}, socket) do
    Repo.delete!(Repo.get!(Contact, id))
    {:noreply, assign(socket, contacts: Repo.all(Contact))}
  end
end
```

A `.vue` file is hybrid when its [`<script setup>`](https://vuejs.org/api/sfc-script-setup.html) declares state the browser owns or changes: a [`ref()`](https://vuejs.org/api/reactivity-core.html#ref), a [`defineModel()`](https://vuejs.org/api/sfc-script-setup.html#definemodel), or a composable's result. Write the script as standard Vue: read [props](https://vuejs.org/guide/components/props.html) through `props.x`, and refs and models through `.value`.

## What runs where

The compiler reads `<script setup>` and classifies each binding:

| In the script | Becomes |
| --- | --- |
| `defineProps(...)` (array, object, or TypeScript form) | props, assigned on the server, which the browser only reads |
| `defineModel("name")` | a model: assigned on the server, which the browser may change |
| `ref(...)` | client state |
| `computed(...)` | client computed, recomputed when props change |
| a function with `"use server"` | a server action |
| a function that writes a model's `.value` | a server action |
| any other function | a client handler |

The server renders the component for the first paint, including the components it imports from `.vue` files; see [Components](templates.md#components). The browser then mounts the Vue component in its place, and LiveView leaves the wrapper's contents alone (`phx-update="ignore"`). The client is a standard Vue 3 component on the virtual DOM, not Vapor mode, so component libraries such as [Reka UI](https://reka-ui.com) work in it as they are.

Props and models reach the client as JSON in the wrapper's `data-pv-props` attribute. They include every model, and every prop the template or the script reads, server actions included, since their bodies run in the browser; a prop nothing reads stays on the server. A value the browser must never see, such as a token, isn't a prop: read it in `handle_event/3`. When an assign changes, LiveView sends the new JSON and the component re-renders.

## Server actions

Data the browser may change, and the server owns, is a [model](https://vuejs.org/guide/components/v-model.html#component-v-model): `const contacts = defineModel("contacts")`, assigned on the server as `contacts`. Name a model after its variable; the LiveView assigns it by that name. In Vue, writing a model asks the component's owner to update it; here the owner is the server.

Calling a server action in the browser does two things:

1. It runs the function's body, as Vue code. Writing a model's `.value` updates it at once, so the UI changes before the server answers: above, `contacts.value = ...` removes the contact.
2. Then it sends the action: an event named after the function, with the function's arguments and the value of each ref or computed it reads, as they were when it was called: `%{"id" => 1}` above. A body that returns or throws first sends nothing, so a guard validates in the browser:

```js
function saveName() {
  "use server"
  if (!dirty.value) return
  project.value = { ...project.value, name: name.value }
}
```

The server-side logic is your `handle_event/3`. Once it has handled the action, the props and models are the server's again: the new assigns it returns replace the browser's optimistic values, and if it left an assign unchanged, declining the change, the optimistic value goes away. While several actions are in flight, the server's props wait for the last answer, so one action's answer doesn't undo another's optimistic change. If the module defines no `handle_event/3`, PhoenixVapor generates no-op handlers for the actions. Once you define one, handle every action it can receive.

Props are read-only, as in Vue: writing `props.contacts`, or `contacts` for a prop the script doesn't declare, is a compile error that points at `defineModel`.

## Single-file components

A `<script lang="elixir">` block is compiled into the LiveView module, so the whole component can live in the `.vue` file. Vue's compiler never sees the block.

```vue
<script lang="elixir">
def mount(_params, _session, socket) do
  {:ok, assign(socket, contacts: Repo.all(Contact))}
end

def handle_event("deleteContact", %{"id" => id}, socket) do
  Repo.delete!(Repo.get!(Contact, id))
  {:noreply, assign(socket, contacts: Repo.all(Contact))}
end
</script>

<script setup>
...
</script>
```

```elixir
defmodule MyAppWeb.ContactsLive do
  use MyAppWeb, :live_view
  use PhoenixVapor, file: "Contacts.vue"
end
```

## The browser side

Each hybrid LiveView compiles its component to `assets/js/hybrid/<Name>.hybrid.js`, named after the `.vue` file. Register the modules with `getHybridHooks`; see [Browser setup](../introduction/getting-started.md#browser-setup). Pass `client_output: "path"` to `use PhoenixVapor` to write them elsewhere, or `client_output: nil` to skip writing them.

A page can mount the same component several times; each mount has its own props and bridge.

## Composables and libraries

A hybrid component is ordinary Vue code, so it uses composables, such as [VueUse](https://vueuse.org)'s, and libraries, such as [es-toolkit](https://es-toolkit.dev). The server renders the first paint without running the component's JavaScript, so it has only what it can know when compiling:

- the refs' initial values, and computeds that read only those;
- the component's constants, such as `const PAGE_SIZE = 20` or `const roles = ["owner", "admin"]`, evaluated once while compiling;
- the props, and computeds that read them, evaluated when rendering;
- script functions with an [Elixir counterpart](templates.md#script-functions-on-the-server), when a computed calls them;
- JavaScript's globals, such as `Math`.

A name bound by any other call, such as `const sortKey = useLocalStorage("sort", "name")` or `const { copy, copied } = useClipboard()`, is state only the browser has, and makes the file hybrid even without a `ref()`. The server's render doesn't have its value, so an expression reading it isn't rendered, and a `v-if` chain whose condition reads it renders no branch: `v-if="sortKey === 'name'"` shows neither its branch nor its `v-else` until the browser mounts. A session replay that recorded the value renders it.

A computed that reads such a name, or an import such as `sortBy`, or a computed built on either, is left out of the server's render, with a compile-time warning naming what it reads that the server lacks:

```
warning: computed `filtered` reads `debouncedSearch`, `sortBy`, which only the browser has,
so the server leaves it, and what reads it, out of the first paint
```

An expression that reads a left-out computed isn't rendered, and a `v-if` chain whose condition reads one renders no branch, so the first paint shows neither the list nor "No contacts match"; the browser renders both when it mounts.

### Elixir counterparts for computeds

To have such a computed in the first paint, define its counterpart in `<script lang="elixir">`: the function of the same name in snake_case, taking the assigns, which hold the props, the refs' values and the computeds before it:

```vue
<script setup>
import { ref, computed } from "vue"
import { sortBy } from "es-toolkit"
import { refDebounced } from "@vueuse/core"

const props = defineProps(["contacts"])
const search = ref("")
const debouncedSearch = refDebounced(search, 150)

const filtered = computed(() =>
  sortBy(props.contacts.filter((c) => c.name.includes(debouncedSearch.value)), ["name"])
)
</script>

<script lang="elixir">
def filtered(%{contacts: contacts, search: search}) do
  contacts
  |> Enum.filter(&String.contains?(&1["name"], search))
  |> Enum.sort_by(& &1["name"])
end
</script>
```

The server calls `filtered/1` on every render, and in a session replay with the recorded state. It reads `search` rather than `debouncedSearch`, which only the browser has. The two versions can drift apart: if they disagree, the list changes when the browser mounts, which is visible but not an error. A computed named after a LiveView callback, such as `render` or `mount`, can't have a counterpart; rename the computed.

How a counterpart reads a key decides what happens when the render doesn't have it:

- A key in the pattern, such as `%{contacts: contacts}`, or read as `assigns.key`, is required. Match on what every render has: props, refs and constants.
- A key read as `assigns[:key]` is optional: `nil` when the render doesn't have it. Read state only the browser has this way, such as a composable's value, and fall back to the default the browser starts with.

```elixir
def sorted(%{contacts: contacts} = assigns) do
  key = assigns[:sortKey] || "name"
  Enum.sort_by(contacts, & &1[key])
end
```

The live render has no `sortKey`, which comes from `useLocalStorage`, so it sorts by name; a replay that recorded `sortKey` sorts by its value. A counterpart that requires state only the browser has, such as `def sorted(%{sortKey: key})`, is never called on the live render, so its computed, and what reads it, is missing from the first paint until a replay; the compiler warns about it. Both kinds of key are recorded.

### Callbacks in the template

An expression only JavaScript evaluates, such as `contact.name.split(" ").map((n) => n[0]).join("")`, runs in QuickBEAM on every server render, with a compile-time warning. Compute it in the data the server sends, or move it into a computed with an Elixir counterpart, to keep rendering in Elixir.

## Session replay

[PhoenixReplay](https://hexdocs.pm/phoenix_replay) records the assigns each render changed, then shows the session by rendering the view with them, without running `mount/3`, events, or the page's JavaScript. Server-only templates, Reactive mode and the full runtime replay as they are, since `render/1` reads only assigns; their QuickBEAM runtimes live in `socket.private`, out of the recording. The mechanism below targets PhoenixReplay 0.6, and needs nothing from your code beyond PhoenixReplay's own setup, including [`replayRecorder`](https://hexdocs.pm/phoenix_replay/recording.html#client-state) in your `app.js`.

A hybrid component's client state lives in the browser, so the server never sees it change. It's recorded through PhoenixReplay's client-state events on `window`, so PhoenixVapor depends on PhoenixReplay neither in Elixir nor in JavaScript:

- Only the client state the server's render reads is recorded: what the template reads, the props of the package components it folded included, and what the computeds and Elixir counterparts it reads read in turn, refs and composables' results alike. State nothing renders, such as a pointer position from `useMouse`, isn't recorded.
- When recording starts with client state, `phx_replay:start`, each hybrid component reports all of that state as a `phx_replay:state` event. Then, as it changes, it reports the latest value of each part that changed once it has been still for PhoenixReplay's debounce, as PhoenixReplay records a form control, so a typed word is one step on the timeline; state that keeps changing is reported at least once per flush interval. Before a server action goes to the server, the state it was sent from is reported, so a replay at that event shows it. A component that mounts during a recording, or whose bridge loads after it started, reports its state then; it reads the `data-phx-replay` attribute PhoenixReplay sets on `<html>` while recording. Before `phx_replay:start`, and after `phx_replay:stop`, nothing is dispatched.
- The state key is `phoenix_vapor:` and the component's wrapper id, such as `phoenix_vapor:pv-Contacts`, which stays the same across reconnects.
- Only plain data is reported: strings, numbers, booleans, `null`, arrays and plain objects. A ref holding anything else, such as a template ref to an element, or `undefined`, is reported as `null`, so the replay doesn't keep an earlier value.

Each hybrid LiveView defines `replay_render/1`, the optional callback of [`PhoenixReplay.Replay.View`](https://hexdocs.pm/phoenix_replay/PhoenixReplay.Replay.View.html), which the replay calls instead of `render/1`, in full at every step: the same template without the client hook and `phx-update="ignore"`, with the state recorded under the component's key in `@phoenix_replay_state` in place of the refs' initial values, and the computeds and their Elixir counterparts evaluated with it. `render/1` never uses recorded state. PhoenixVapor doesn't declare the behaviour, which would need PhoenixReplay as a dependency.

What a replay doesn't show:

- A package component the server rendered when compiling, such as Reka's tabs or switch, follows the recorded state its props read when their types are sets of values, as it [folds once for each](templates.md#once-for-each-value); a prop typed `string` keeps its initial value throughout, and so does state the component holds itself, such as an uncontrolled `TabsRoot` with only a `default-value`. An open dialog's content inside `DialogPortal` shows in place; what a component works out only in the browser, such as a `SelectValue`'s label, doesn't.
- An optimistic change to a model that the server then declined: the model was never server state, so the replay shows the server's value throughout.

PhoenixReplay also records form controls on its own, under `"phx_replay:inputs"`, and puts their values back into the replayed page: those with an `id`, or a form `id` and a `name`. An input bound to a ref a hybrid component already reports, such as a search box with `v-model`, is recorded twice then, at the same moments, as both wait for the same debounce; leave its `id` off, or mark it `data-phx-replay-ignore`, to keep the component's report the only one.

PhoenixReplay drops a report whose changes exceed 8,192 bytes of JSON. Each report carries only the refs that changed, so this matters only for a single ref holding that much, such as a large list kept in a ref: changes to it aren't recorded.

