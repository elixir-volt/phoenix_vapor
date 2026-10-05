<script setup>
import { ref, computed } from "vue"
import { sortBy } from "es-toolkit"
import { refDebounced, useLocalStorage, useMouse } from "@vueuse/core"

const props = defineProps(["contacts"])

const search = ref("")
const debouncedSearch = refDebounced(search, 150)
const sortKey = useLocalStorage("contacts:sort", "name")
const { x, y } = useMouse()

// Reads a composable's result, which only the browser has.
const matching = computed(() => props.contacts.filter(c => c.name.includes(debouncedSearch.value)))
// Calls an import, which the server's runtime doesn't load.
const names = computed(() => sortBy(props.contacts, ["name"]).map(c => c.name))
// Sorted by a composable's value, which the server has only in a replay.
const sorted = computed(() => sortBy(props.contacts, [sortKey.value]).map(c => c.name))
// A constant and a script function with an Elixir counterpart are known to
// the server too.
const PAGE = 2
const firstPage = computed(() => props.contacts.slice(0, PAGE).map(c => c.name).join(", "))
function initial(name) { return name[0] }
const firstInitial = computed(() => initial(props.contacts[0].name))
// Reads a composable's value that only its counterpart reads, as optional.
const theme = useLocalStorage("theme", "light")
const themed = computed(() => props.contacts.map(c => `${c.name}:${theme.value}`).join(", "))
// Reads only what the server has.
const total = computed(() => props.contacts.length)
</script>

<script lang="elixir">
# The server's versions of the computeds the browser computes with
# VueUse and es-toolkit.
def matching(%{contacts: contacts, search: search}),
  do: Enum.filter(contacts, &String.contains?(&1["name"], search))

def names(%{contacts: contacts}), do: contacts |> Enum.map(& &1["name"]) |> Enum.sort()

def initial(name), do: String.first(name)

def sorted(%{contacts: contacts, sortKey: key}),
  do: contacts |> Enum.sort_by(& &1[key]) |> Enum.map(& &1["name"])

# theme may be missing: the live render renders the default.
def themed(%{contacts: contacts} = assigns),
  do: Enum.map_join(contacts, ", ", &"#{&1["name"]}:#{assigns[:theme] || "light"}")
</script>

<template>
  <div>
    <p>{{ total }} contacts, sorted by {{ sortKey }}</p>
    <p v-if="matching.length === 0">No contacts match</p>
    <p v-else>{{ matching.length }} match</p>
    <ul><li v-for="name in names" :key="name">{{ name }}</li></ul>
    <input :value="search" />
    <p>first page: {{ firstPage }}, of {{ PAGE }}</p>
    <p>initial: {{ firstInitial }}</p>
    <p v-if="sortKey === 'name'">by name</p>
    <p v-else>by something else</p>
    <ol><li v-for="name in sorted" :key="name">{{ name }}</li></ol>
    <p>themed: {{ themed }}</p>
  </div>
</template>
