<script setup>
import { ref, computed } from "vue"

const props = defineProps(["contacts", "title"])

const search = ref("")
const sortKey = ref("name")
const selectedIds = ref([])
const showDialog = ref(false)

const filtered = computed(() => {
  const term = search.value.toLowerCase()
  return (props.contacts || [])
    .filter(c => c.name.toLowerCase().includes(term))
    .sort((a, b) => (a[sortKey.value] || "").localeCompare(b[sortKey.value] || ""))
})

const selectedCount = computed(() => selectedIds.value.length)

function clearSearch() {
  search.value = ""
}

function toggleSelect(id) {
  const idx = selectedIds.value.indexOf(id)
  if (idx === -1) {
    selectedIds.value = [...selectedIds.value, id]
  } else {
    selectedIds.value = selectedIds.value.filter(x => x !== id)
  }
}

function openDialog() {
  showDialog.value = true
}

function closeDialog() {
  showDialog.value = false
}

function deleteContact(id) {
  "use server"
  props.contacts = props.contacts.filter(c => c.id !== id)
}

function deleteSelected() {
  "use server"
  props.contacts = props.contacts.filter(c => !selectedIds.value.includes(c.id))
}
</script>

<template>
  <div>
    <h1>{{ title }}</h1>
    <input :value="search" @input="search = $event.target.value" placeholder="Search..." />
    <select :value="sortKey" @change="sortKey = $event.target.value">
      <option value="name">Name</option>
      <option value="email">Email</option>
    </select>
    <button @click="clearSearch">Clear</button>
    <p>{{ filtered.length }} of {{ props.contacts.length }} contacts</p>
    <p v-if="selectedCount > 0">{{ selectedCount }} selected</p>
    <ul>
      <li v-for="contact in filtered" :key="contact.id">
        <input type="checkbox" :checked="selectedIds.includes(contact.id)" @change="toggleSelect(contact.id)" />
        <span>{{ contact.name }}</span>
        <span>{{ contact.email }}</span>
        <button @click="deleteContact(contact.id)">Delete</button>
      </li>
    </ul>
    <div v-if="showDialog">
      <p>Confirm delete?</p>
      <button @click="closeDialog">Cancel</button>
    </div>
    <button @click="openDialog">Open Dialog</button>
    <button @click="deleteSelected">Delete Selected</button>
  </div>
</template>
