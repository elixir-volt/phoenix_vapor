<script setup lang="ts">
import { ref, computed, useTemplateRef } from "vue"
import { groupBy, sortBy } from "es-toolkit"
import { refDebounced, useLocalStorage, useClipboard, onKeyStroke } from "@vueuse/core"
import {
  DialogRoot, DialogPortal, DialogOverlay, DialogContent, DialogTitle, DialogDescription, DialogClose,
} from "reka-ui"
import Button from "@/ui/Button.vue"
import Badge from "@/ui/Badge.vue"

type Contact = { id: number; name: string; email: string; company: string; role: string; initials: string }
type SortKey = "name" | "company" | "role"

// The server owns the contacts; deleting changes them through a server action.
const contacts = defineModel<Contact[]>("contacts", { required: true })

const search = ref("")
const query = refDebounced(search, 150)
const sortKey = useLocalStorage<SortKey>("contacts:sort", "name")
const selectedIds = ref<number[]>([])
const deleteTarget = ref<Contact | null>(null)
const searchInput = useTemplateRef<HTMLInputElement>("searchInput")
const { copy, copied } = useClipboard({ copiedDuring: 1500 })

// "/" focuses the search, as in most web apps.
onKeyStroke("/", (event) => {
  if (document.activeElement === searchInput.value) return
  event.preventDefault()
  searchInput.value?.focus()
})

const sortOptions: { value: SortKey; label: string }[] = [
  { value: "name", label: "Name" },
  { value: "company", label: "Company" },
  { value: "role", label: "Role" },
]

const matching = computed(() => {
  const term = query.value.trim().toLowerCase()
  const found = contacts.value.filter((c) =>
    [c.name, c.email, c.company].some((field) => field.toLowerCase().includes(term)),
  )
  return sortBy(found, [sortKey.value])
})

const groups = computed(() =>
  Object.entries(groupBy(matching.value, (c) => c.company))
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([company, contacts]) => ({ company, contacts })),
)

const allSelected = computed(
  () => matching.value.length > 0 && matching.value.every((c) => selectedIds.value.includes(c.id)),
)

function toggle(id: number) {
  selectedIds.value = selectedIds.value.includes(id)
    ? selectedIds.value.filter((x) => x !== id)
    : [...selectedIds.value, id]
}

function toggleAll() {
  selectedIds.value = allSelected.value ? [] : matching.value.map((c) => c.id)
}

function deleteContacts(ids: number[]) {
  "use server"
  contacts.value = contacts.value.filter((c) => !ids.includes(c.id))
}

function confirmDelete() {
  if (!deleteTarget.value) return
  const id = deleteTarget.value.id
  deleteContacts([id])
  selectedIds.value = selectedIds.value.filter((x) => x !== id)
  deleteTarget.value = null
}

function deleteSelected() {
  deleteContacts(selectedIds.value)
  selectedIds.value = []
}
</script>

<script lang="elixir">
# The server's versions of the computeds, for the first paint and for a
# session replay. Every render has the contacts and the search, a ref; the
# sort order lives in localStorage, so only a replay has it: read it as
# optional, and fall back to the order the browser starts with.
def matching(%{contacts: contacts, search: search} = assigns) do
  term = search |> String.trim() |> String.downcase()

  key =
    case assigns[:sortKey] do
      "company" -> :company
      "role" -> :role
      _name -> :name
    end

  contacts
  |> Enum.filter(fn contact ->
    Enum.any?([contact.name, contact.email, contact.company], &(&1 |> String.downcase() |> String.contains?(term)))
  end)
  |> Enum.sort_by(&Map.fetch!(&1, key))
end

def groups(%{matching: matching}) do
  matching
  |> Enum.group_by(& &1.company)
  |> Enum.sort_by(&elem(&1, 0))
  |> Enum.map(fn {company, contacts} -> %{company: company, contacts: contacts} end)
end
</script>

<template>
  <div class="space-y-5">
    <div class="flex items-end justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold tracking-tight text-zinc-900">Contacts</h1>
        <p class="text-sm text-zinc-500">{{ matching.length }} of {{ contacts.length }} contacts</p>
      </div>
      <Badge v-if="copied" tone="success">Email copied</Badge>
    </div>

    <div class="flex flex-wrap items-center gap-3">
      <div class="relative flex-1">
        <input
          ref="searchInput"
          aria-label="Search contacts"
          v-model="search"
          type="search"
          placeholder="Search contacts..."
          class="h-9 w-full rounded-md border border-zinc-300 px-3 pr-10 text-sm"
        />
        <kbd class="absolute right-2 top-1/2 -translate-y-1/2 rounded border border-zinc-200 px-1.5 text-xs text-zinc-400">/</kbd>
      </div>
      <div class="inline-flex gap-1 rounded-md bg-zinc-100 p-1" role="group" aria-label="Sort by">
        <Button
          v-for="option in sortOptions"
          :key="option.value"
          size="sm"
          :variant="sortKey === option.value ? 'default' : 'ghost'"
          @click="sortKey = option.value"
        >
          {{ option.label }}
        </Button>
      </div>
      <Button v-if="search" variant="ghost" size="sm" @click="search = ''">Clear</Button>
    </div>

    <div v-if="selectedIds.length > 0" class="flex items-center gap-3 rounded-md border border-indigo-200 bg-indigo-50 px-4 py-2 text-sm">
      <span>{{ selectedIds.length }} selected</span>
      <Button variant="destructive" size="sm" @click="deleteSelected">Delete selected</Button>
      <Button variant="ghost" size="sm" @click="selectedIds = []">Clear selection</Button>
    </div>

    <label class="flex w-fit items-center gap-2 text-sm text-zinc-500">
      <input type="checkbox" :checked="allSelected" @change="toggleAll" />
      Select all
    </label>

    <section v-for="group in groups" :key="group.company" class="space-y-1">
      <h2 class="text-xs font-semibold uppercase tracking-wide text-zinc-400">{{ group.company }}</h2>
      <ul class="divide-y divide-zinc-100 rounded-lg border border-zinc-200 bg-white">
        <li v-for="contact in group.contacts" :key="contact.id" class="flex items-center gap-3 px-4 py-2">
          <input type="checkbox" :checked="selectedIds.includes(contact.id)" @change="toggle(contact.id)" />
          <span class="flex size-8 items-center justify-center rounded-full bg-zinc-100 text-xs font-semibold text-zinc-600">
            {{ contact.initials }}
          </span>
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-medium text-zinc-900">{{ contact.name }}</p>
            <button type="button" class="truncate text-xs text-zinc-500 hover:text-zinc-900" title="Copy email" @click="copy(contact.email)">
              {{ contact.email }}
            </button>
          </div>
          <Badge>{{ contact.role }}</Badge>
          <Button variant="ghost" size="sm" :aria-label="`Delete ${contact.name}`" @click="deleteTarget = contact">Delete</Button>
        </li>
      </ul>
    </section>

    <p v-if="matching.length === 0" class="py-10 text-center text-sm text-zinc-500">No contacts match</p>

    <DialogRoot :open="deleteTarget !== null" @update:open="(open: boolean) => { if (!open) deleteTarget = null }">
      <DialogPortal>
        <DialogOverlay class="fixed inset-0 bg-black/40" />
        <DialogContent class="fixed left-1/2 top-1/2 w-full max-w-sm -translate-x-1/2 -translate-y-1/2 rounded-lg bg-white p-6 shadow-xl">
          <DialogTitle class="text-lg font-semibold">Delete contact?</DialogTitle>
          <DialogDescription class="mt-1 text-sm text-zinc-500">
            {{ deleteTarget?.name }} will be removed for everyone in the workspace.
          </DialogDescription>
          <div class="mt-5 flex justify-end gap-2">
            <DialogClose as-child><Button variant="outline">Cancel</Button></DialogClose>
            <Button variant="destructive" @click="confirmDelete">Delete</Button>
          </div>
        </DialogContent>
      </DialogPortal>
    </DialogRoot>
  </div>
</template>
