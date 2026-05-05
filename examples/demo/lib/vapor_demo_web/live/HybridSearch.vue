<script setup>
import { ref, computed } from "vue"

const props = defineProps(["contacts", "title"])

const search = ref("")
const sortKey = ref("name")

const filtered = computed(() => {
  const term = search.value.toLowerCase()
  return (props.contacts || [])
    .filter(c => c.name.toLowerCase().includes(term) || c.email.toLowerCase().includes(term) || c.company.toLowerCase().includes(term))
    .sort((a, b) => {
      const aVal = a[sortKey.value] || ""
      const bVal = b[sortKey.value] || ""
      return aVal.localeCompare(bVal)
    })
})

function clearSearch() {
  search.value = ""
}
</script>

<template>
  <div class="max-w-4xl mx-auto p-6 space-y-5">
    <h1 class="text-2xl font-bold">{{ title }}</h1>

    <div class="flex gap-3">
      <input
        :value="search"
        @input="search = $event.target.value"
        placeholder="Search contacts..."
        class="flex-1 px-4 py-2 border rounded-lg"
      />
      <select :value="sortKey" @change="sortKey = $event.target.value" class="px-3 py-2 border rounded-lg">
        <option value="name">Sort by name</option>
        <option value="email">Sort by email</option>
        <option value="company">Sort by company</option>
      </select>
      <button v-if="search" @click="clearSearch" class="px-3 py-2 border rounded-lg">
        Clear
      </button>
    </div>

    <p class="text-sm text-gray-500">{{ filtered.length }} of {{ props.contacts.length }} contacts</p>

    <div class="border rounded-lg divide-y">
      <div v-for="contact in filtered" :key="contact.id" class="flex items-center gap-4 px-4 py-3">
        <div class="font-medium">{{ contact.name }}</div>
        <div class="text-gray-500">{{ contact.email }}</div>
        <div class="text-gray-400 ml-auto">{{ contact.company }}</div>
      </div>
      <div v-if="filtered.length === 0" class="px-4 py-8 text-center text-gray-400">
        No contacts match your search
      </div>
    </div>
  </div>
</template>
