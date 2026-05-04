<script setup>
import { ref, computed } from "vue"

defineProps(["users", "title"])

const search = ref("")
const filtered = computed(() => users.filter(u => u.name.includes(search.value)))

function clearSearch() {
  search.value = ""
}

function deleteUser(id) {
  "use server"
  users = users.filter(u => u.id !== id)
}
</script>

<template>
  <div>
    <h1>{{ title }}</h1>
    <input :value="search" @input="search = $event.target.value" />
    <p>{{ filtered.length }} results</p>
    <button @click="clearSearch">Clear</button>
    <button @click="deleteUser(1)">Delete</button>
  </div>
</template>
