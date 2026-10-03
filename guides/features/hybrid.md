# Hybrid Mode

Hybrid mode splits a `.vue` component between the server and the browser. The server owns the data, passed in as props, and Vue in the browser owns UI state. Searching, sorting, and selecting happen in the browser without a round trip; changes to the data go through server actions over the LiveView socket.

```vue
<script setup>
import { ref, computed } from "vue"

const props = defineProps(["contacts"])
const search = ref("")

const filtered = computed(() =>
  props.contacts.filter(c => c.name.toLowerCase().includes(search.value.toLowerCase()))
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

A `.vue` file is hybrid when its `<script setup>` declares a `ref()`. Write the script as standard Vue: read props through `props.x` and refs through `.value`.

## What runs where

The compiler reads `<script setup>` and classifies each binding:

| In the script | Becomes |
| --- | --- |
| `defineProps(...)` (array, object, or TypeScript form) | props, assigned on the server |
| `ref(...)` | client state |
| `computed(...)` | client computed, recomputed when props change |
| a function with `"use server"` | a server action |
| a function that assigns a prop | a server action |
| any other function | a client handler |

The server renders the whole component for the first paint. The browser then mounts the Vue component in its place, and LiveView leaves the wrapper's contents alone (`phx-update="ignore"`).

Props reach the client as JSON in the wrapper's `data-pv-props` attribute. They include every prop the template or client-side code reads; props read only by server actions stay on the server. When an assign changes, LiveView sends the new JSON and the component re-renders.

## Server actions

Calling a server action in the browser does two things:

1. It applies the action's prop assignments locally, so the UI updates at once. Above, `props.contacts = ...` removes the contact before the server answers.
2. It pushes an event named after the function, with the function's arguments and the current value of each ref or computed it reads: `%{"id" => 1}` above.

The server-side logic is your `handle_event/3`, and the new assigns it returns flow back as props. The function body in the `.vue` file only describes the optimistic update. If the module defines no `handle_event/3`, PhoenixVapor generates no-op handlers for the actions. Once you define one, handle every action it can receive.

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
