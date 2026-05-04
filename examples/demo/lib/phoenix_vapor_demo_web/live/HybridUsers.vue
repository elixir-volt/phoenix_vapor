<script setup>
import { ref, computed } from "vue"

defineProps(["users", "title"])

const search = ref("")
const sortKey = ref("name")

const filtered = computed(() => {
  const term = search.value.toLowerCase()
  return users
    .filter(u => u.name.toLowerCase().includes(term))
    .sort((a, b) => a[sortKey.value].localeCompare(b[sortKey.value]))
})

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
    <div>
      <input :value="search" @input="search = $event.target.value" placeholder="Filter users..." />
      <select :value="sortKey" @change="sortKey = $event.target.value">
        <option value="name">Sort by name</option>
        <option value="email">Sort by email</option>
      </select>
      <button @click="clearSearch">Clear</button>
    </div>
    <p>{{ filtered.length }} of {{ users.length }} users shown</p>
    <ul>
      <li v-for="user in filtered" :key="user.id">
        <span>{{ user.name }}</span>
        <span>{{ user.email }}</span>
        <button @click="deleteUser(user.id)">×</button>
      </li>
    </ul>
  </div>
</template>
