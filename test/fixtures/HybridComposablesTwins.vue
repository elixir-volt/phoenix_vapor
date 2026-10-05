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
// Reads only what the server has.
const total = computed(() => props.contacts.length)
</script>

<script lang="elixir">
# The server's versions of the computeds the browser computes with
# VueUse and es-toolkit.
def matching(%{contacts: contacts, search: search}),
  do: Enum.filter(contacts, &String.contains?(&1["name"], search))

def names(%{contacts: contacts}), do: contacts |> Enum.map(& &1["name"]) |> Enum.sort()
</script>

<template>
  <div>
    <p>{{ total }} contacts, sorted by {{ sortKey }}</p>
    <p v-if="matching.length === 0">No contacts match</p>
    <p v-else>{{ matching.length }} match</p>
    <ul><li v-for="name in names" :key="name">{{ name }}</li></ul>
    <input :value="search" />
  </div>
</template>
