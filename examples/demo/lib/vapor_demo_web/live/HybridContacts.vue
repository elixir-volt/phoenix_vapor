<script setup>
import { ref, computed } from "vue"
import {
  DialogRoot, DialogTrigger, DialogContent, DialogTitle,
  DialogDescription, DialogClose, DialogPortal, DialogOverlay,
} from "reka-ui"
import {
  TooltipRoot, TooltipTrigger, TooltipContent, TooltipPortal, TooltipProvider,
} from "reka-ui"

const props = defineProps(["contacts"])

const search = ref("")
const sortKey = ref("name")
const selectedIds = ref([])
const deleteTarget = ref(null)

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
const allSelected = computed(() => filtered.value.length > 0 && selectedCount.value === filtered.value.length)

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

function toggleAll() {
  if (allSelected.value) {
    selectedIds.value = []
  } else {
    selectedIds.value = filtered.value.map(c => c.id)
  }
}

function askDelete(id) {
  deleteTarget.value = id
}

function cancelDelete() {
  deleteTarget.value = null
}

function deleteContact(id) {
  "use server"
  props.contacts = props.contacts.filter(c => c.id !== id)
}

function confirmDelete() {
  if (deleteTarget.value) {
    deleteContact(deleteTarget.value)
    selectedIds.value = selectedIds.value.filter(x => x !== deleteTarget.value)
    deleteTarget.value = null
  }
}

function deleteSelected() {
  "use server"
  props.contacts = props.contacts.filter(c => !selectedIds.value.includes(c.id))
}

function confirmDeleteSelected() {
  deleteSelected()
  selectedIds.value = []
}
</script>

<template>
  <TooltipProvider :delay-duration="300">
    <div class="max-w-4xl mx-auto p-6 space-y-5">
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
            class="w-full px-4 py-2 pl-10 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none transition-colors"
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
          class="px-3 py-2 text-sm text-gray-600 hover:text-gray-900 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
        >
          Clear
        </button>
      </div>

      <div v-if="selectedCount > 0" class="flex items-center gap-3 px-4 py-2.5 bg-blue-50 border border-blue-200 rounded-lg">
        <span class="text-sm font-medium text-blue-700">{{ selectedCount }} selected</span>
        <button @click="toggleAll" class="text-sm text-blue-600 hover:text-blue-800 underline">
          Deselect all
        </button>
        <button @click="confirmDeleteSelected" class="ml-auto text-sm px-3 py-1.5 bg-red-600 text-white rounded-md hover:bg-red-700 transition-colors">
          Delete selected
        </button>
      </div>

      <div class="flex items-center gap-2 text-sm text-gray-500">
        <span>{{ filtered.length }} of {{ props.contacts.length }} contacts</span>
        <button v-if="!allSelected && filtered.length > 0" @click="toggleAll" class="text-blue-600 hover:underline">
          Select all
        </button>
      </div>

      <div class="border border-gray-200 rounded-lg overflow-hidden">
        <div
          v-for="contact in filtered"
          :key="contact.id"
          :class="[
            'flex items-center gap-4 px-4 py-3 border-b border-gray-100 last:border-b-0 transition-colors',
            selectedIds.includes(contact.id) ? 'bg-blue-50/50' : 'hover:bg-gray-50'
          ]"
        >
          <input
            type="checkbox"
            :checked="selectedIds.includes(contact.id)"
            @change="toggleSelect(contact.id)"
            class="w-4 h-4 rounded border-gray-300 text-blue-600 focus:ring-blue-500"
          />

          <div :class="['w-9 h-9 rounded-full flex items-center justify-center text-sm font-medium text-white shrink-0', contact.color]">
            {{ contact.name.split(' ').map(n => n[0]).join('') }}
          </div>

          <div class="flex-1 min-w-0">
            <div class="font-medium text-gray-900 truncate">{{ contact.name }}</div>
            <div class="text-sm text-gray-500 truncate">{{ contact.email }}</div>
          </div>

          <div class="hidden sm:block text-sm text-gray-500 w-28 truncate">{{ contact.company }}</div>
          <div class="hidden md:block text-sm text-gray-400 w-28 truncate">{{ contact.role }}</div>

          <TooltipRoot>
            <TooltipTrigger as-child>
              <button
                @click="askDelete(contact.id)"
                class="p-1.5 text-gray-400 hover:text-red-600 rounded-md hover:bg-red-50 transition-colors"
              >
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                </svg>
              </button>
            </TooltipTrigger>
            <TooltipPortal>
              <TooltipContent side="left" class="bg-gray-900 text-white text-xs px-2 py-1 rounded shadow-lg">
                Delete contact
              </TooltipContent>
            </TooltipPortal>
          </TooltipRoot>
        </div>

        <div v-if="filtered.length === 0" class="px-4 py-12 text-center">
          <p class="text-gray-400">No contacts match your search</p>
          <button v-if="search" @click="clearSearch" class="mt-2 text-sm text-blue-600 hover:underline">Clear search</button>
        </div>
      </div>

      <!-- Reka UI Dialog for delete confirmation -->
      <DialogRoot :open="deleteTarget !== null" @update:open="v => { if (!v) cancelDelete() }">
        <DialogPortal>
          <DialogOverlay class="fixed inset-0 bg-black/40 z-50" />
          <DialogContent class="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-white rounded-xl p-6 shadow-2xl max-w-sm w-full mx-4 z-50 focus:outline-none">
            <DialogTitle class="text-lg font-semibold text-gray-900">Delete contact?</DialogTitle>
            <DialogDescription class="text-sm text-gray-500 mt-2">
              This will permanently remove the contact. This action cannot be undone.
            </DialogDescription>
            <div class="mt-5 flex justify-end gap-3">
              <DialogClose as-child>
                <button @click="cancelDelete" class="px-4 py-2 text-sm font-medium border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors">
                  Cancel
                </button>
              </DialogClose>
              <button @click="confirmDelete" class="px-4 py-2 text-sm font-medium bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors">
                Delete
              </button>
            </div>
          </DialogContent>
        </DialogPortal>
      </DialogRoot>
    </div>
  </TooltipProvider>
</template>
