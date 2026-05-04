<script setup>
import { ref, computed } from "vue"

const props = defineProps(["contacts"])

const search = ref("")
const sortKey = ref("name")
const selectedIds = ref([])
const showDeleteConfirm = ref(false)
const pendingDeleteId = ref(null)

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

function selectAll() {
  selectedIds.value = filtered.value.map(c => c.id)
}

function deselectAll() {
  selectedIds.value = []
}

function confirmDelete(id) {
  pendingDeleteId.value = id
  showDeleteConfirm.value = true
}

function cancelDelete() {
  showDeleteConfirm.value = false
  pendingDeleteId.value = null
}

function deleteContact(id) {
  "use server"
  props.contacts = props.contacts.filter(c => c.id !== id)
}

function executeDelete() {
  if (pendingDeleteId.value) {
    deleteContact(pendingDeleteId.value)
    selectedIds.value = selectedIds.value.filter(x => x !== pendingDeleteId.value)
  }
  showDeleteConfirm.value = false
  pendingDeleteId.value = null
}

function deleteSelected() {
  "use server"
  props.contacts = props.contacts.filter(c => !selectedIds.value.includes(c.id))
}

function executeDeleteSelected() {
  deleteSelected()
  selectedIds.value = []
}
</script>

<template>
  <div class="max-w-4xl mx-auto p-6 space-y-6">
    <div>
      <h1 class="text-2xl font-bold tracking-tight">Contacts</h1>
      <p class="text-sm text-gray-500 mt-1">
        Hybrid mode — search and sort are instant (client), delete goes through the server.
      </p>
    </div>

    <div class="flex items-center gap-3">
      <div class="relative flex-1">
        <input
          :value="search"
          @input="search = $event.target.value"
          placeholder="Search contacts..."
          class="w-full px-4 py-2 pl-10 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
        />
        <svg class="absolute left-3 top-2.5 w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
        </svg>
      </div>
      <select
        :value="sortKey"
        @change="sortKey = $event.target.value"
        class="px-3 py-2 border border-gray-300 rounded-lg bg-white focus:ring-2 focus:ring-blue-500 outline-none"
      >
        <option value="name">Sort by name</option>
        <option value="email">Sort by email</option>
        <option value="company">Sort by company</option>
        <option value="role">Sort by role</option>
      </select>
      <button
        v-if="search"
        @click="clearSearch"
        class="px-3 py-2 text-sm text-gray-600 hover:text-gray-900 border border-gray-300 rounded-lg hover:bg-gray-50"
      >
        Clear
      </button>
    </div>

    <div v-if="selectedCount > 0" class="flex items-center gap-3 px-4 py-2 bg-blue-50 border border-blue-200 rounded-lg">
      <span class="text-sm font-medium text-blue-700">{{ selectedCount }} selected</span>
      <button @click="deselectAll" class="text-sm text-blue-600 hover:text-blue-800 underline">
        Deselect all
      </button>
      <button @click="executeDeleteSelected" class="ml-auto text-sm px-3 py-1 bg-red-600 text-white rounded hover:bg-red-700">
        Delete selected
      </button>
    </div>

    <div class="text-sm text-gray-500">
      {{ filtered.length }} of {{ props.contacts.length }} contacts
      <button v-if="filtered.length > 0 && selectedCount !== filtered.length" @click="selectAll" class="ml-2 text-blue-600 hover:underline">
        Select all
      </button>
    </div>

    <div class="border border-gray-200 rounded-lg overflow-hidden divide-y divide-gray-200">
      <div
        v-for="contact in filtered"
        :key="contact.id"
        :class="['flex items-center gap-4 px-4 py-3 hover:bg-gray-50 transition-colors', selectedIds.includes(contact.id) ? 'bg-blue-50' : '']"
      >
        <input
          type="checkbox"
          :checked="selectedIds.includes(contact.id)"
          @change="toggleSelect(contact.id)"
          class="w-4 h-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
        />
        <div
          :class="['w-9 h-9 rounded-full flex items-center justify-center text-sm font-medium text-white', contact.color || 'bg-gray-400']"
        >
          {{ contact.name.split(' ').map(n => n[0]).join('') }}
        </div>
        <div class="flex-1 min-w-0">
          <div class="font-medium text-gray-900 truncate">{{ contact.name }}</div>
          <div class="text-sm text-gray-500 truncate">{{ contact.email }}</div>
        </div>
        <div class="hidden sm:block text-sm text-gray-500 w-32 truncate">{{ contact.company }}</div>
        <div class="hidden md:block text-sm text-gray-500 w-28 truncate">{{ contact.role }}</div>
        <button
          @click="confirmDelete(contact.id)"
          class="p-1.5 text-gray-400 hover:text-red-600 rounded hover:bg-red-50 transition-colors"
        >
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
        </button>
      </div>

      <div v-if="filtered.length === 0" class="px-4 py-8 text-center text-gray-500">
        <p>No contacts found</p>
        <button v-if="search" @click="clearSearch" class="mt-2 text-sm text-blue-600 hover:underline">Clear search</button>
      </div>
    </div>

    <div v-if="showDeleteConfirm" class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="fixed inset-0 bg-black/50" @click="cancelDelete"></div>
      <div class="relative bg-white rounded-lg p-6 shadow-xl max-w-sm w-full mx-4">
        <h3 class="text-lg font-semibold">Delete contact?</h3>
        <p class="text-sm text-gray-500 mt-2">This action cannot be undone.</p>
        <div class="mt-4 flex justify-end gap-2">
          <button @click="cancelDelete" class="px-4 py-2 text-sm border border-gray-300 rounded-lg hover:bg-gray-50">
            Cancel
          </button>
          <button @click="executeDelete" class="px-4 py-2 text-sm bg-red-600 text-white rounded-lg hover:bg-red-700">
            Delete
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
