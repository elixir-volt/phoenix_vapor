<script setup lang="ts">
import { ref, computed } from "vue"
import FilterMenu from "@/ui/FilterMenu.vue"
import ActionMenu from "@/ui/ActionMenu.vue"
import StatusIcon from "@/ui/StatusIcon.vue"
import PriorityIcon from "@/ui/PriorityIcon.vue"
import Avatar from "@/ui/Avatar.vue"

type Person = { id: number; name: string; initials: string; color: string }
type Issue = {
  id: number
  key: string
  title: string
  status: string
  priority: string
  assignee: Person | null
  labels: string[]
  rank: number
  updated: number
  when: string
}

// The server owns the issues; a bulk move goes through a server action.
const issues = defineModel<Issue[]>("issues", { required: true })
defineProps<{ heading: string; parent: { href: string; name: string } | null }>()

// Sorting and selection are the browser's.
const sort = ref<"priority" | "updated">("priority")
const selected = ref<number[]>([])

const sortOptions = [
  { value: "priority", label: "Priority" },
  { value: "updated", label: "Last updated" },
]
const sortLabels: Record<string, string> = { priority: "Priority", updated: "Last updated" }

const statusOptions = [
  { value: "backlog", label: "Backlog" },
  { value: "todo", label: "Todo" },
  { value: "in_progress", label: "In Progress" },
  { value: "in_review", label: "In Review" },
  { value: "done", label: "Done" },
]

const labelColors: Record<string, string> = {
  Bug: "#f2555a",
  Auth: "#f5a524",
  API: "#4c9bff",
  UI: "#b48cff",
  Realtime: "#3dd68c",
}

// Issues by status, in board order, sorted within each group.
const groups = computed(() =>
  statusOptions
    .map((group) => ({
      status: group.value,
      label: group.label,
      issues: issues.value
        .filter((issue) => issue.status === group.value)
        .sort((a, b) => (sort.value === "priority" ? b.rank - a.rank : 0) || b.updated - a.updated),
    }))
    .filter((group) => group.issues.length > 0),
)


function toggle(id: number) {
  selected.value = selected.value.includes(id)
    ? selected.value.filter((x) => x !== id)
    : [...selected.value, id]
}

function moveIssues(ids: number[], status: string) {
  "use server"
  issues.value = issues.value.map((issue) => (ids.includes(issue.id) ? { ...issue, status } : issue))
}

function moveSelected(status: string) {
  moveIssues(selected.value, status)
  selected.value = []
}
</script>

<script lang="elixir">
# The groups the server renders with: by status, sorted by the
# sort the browser starts with, or the one a replay recorded.
def groups(%{issues: issues, sort: sort}) do
  for {status, label} <- [
        {"backlog", "Backlog"},
        {"todo", "Todo"},
        {"in_progress", "In Progress"},
        {"in_review", "In Review"},
        {"done", "Done"}
      ],
      group = Enum.filter(issues, &(&1.status == status)),
      group != [] do
    sorted =
      if sort == "priority",
        do: Enum.sort_by(group, &{-&1.rank, -&1.updated}),
        else: Enum.sort_by(group, &(-&1.updated))

    %{status: status, label: label, issues: sorted}
  end
end
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <header class="flex flex-wrap items-center gap-3 border-b border-line px-5 py-2.5">
      <div class="flex items-center gap-2 text-[13.5px]">
        <template v-if="parent">
          <span class="text-muted">{{ parent.name }}</span>
          <span class="text-faint">/</span>
        </template>
        <span class="font-medium">{{ heading }}</span>
      </div>
      <div data-render="folded" data-render-label="folded · Reka menu" data-render-tag="below" class="ml-2 p-1">
        <FilterMenu v-model="sort" label="Sort" :options="sortOptions" :current="sortLabels[sort]" />
      </div>
      <nav v-if="parent" aria-label="View" class="ml-auto flex overflow-hidden rounded-md border border-edge">
        <a
          :href="parent.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="flex h-7 items-center px-2.5 text-[12.5px] text-muted hover:text-fg"
        >Board</a>
        <span class="flex h-7 items-center bg-raised px-2.5 text-[12.5px] text-fg">List</span>
      </nav>
    </header>

    <section
      data-render="hybrid"
      data-render-label="hybrid · Vue in the browser"
      class="min-h-0 flex-1 pb-20"
    >
      <p v-if="issues.length === 0" class="px-6 py-16 text-center text-faint">Nothing here.</p>
      <div v-for="group in groups" :key="group.status">
        <h2 class="sticky top-0 z-10 flex h-9 items-center gap-2 border-b border-line bg-panel px-5 text-[12.5px]">
          <StatusIcon :status="group.status" />
          <span class="font-medium">{{ group.label }}</span>
          <span class="text-faint">{{ group.issues.length }}</span>
        </h2>
        <ul>
          <li
            v-for="issue in group.issues"
            :key="issue.id"
            class="group flex h-10 items-center gap-3 border-b border-line px-5 hover:bg-panel"
            :class="selected.includes(issue.id) ? 'bg-accent-soft hover:bg-accent-soft' : ''"
          >
            <input
              type="checkbox"
              :checked="selected.includes(issue.id)"
              :aria-label="`Select ${issue.key}`"
              class="size-3.5 accent-[var(--accent)] opacity-40 group-hover:opacity-100 checked:opacity-100"
              @change="toggle(issue.id)"
            />
            <PriorityIcon :priority="issue.priority" />
            <span class="w-16 shrink-0 font-mono text-[11.5px] text-faint">{{ issue.key }}</span>
            <a
              :href="`/issue/${issue.key}`"
              data-phx-link="redirect"
              data-phx-link-state="push"
              class="min-w-0 truncate text-fg-2 hover:text-fg"
            >{{ issue.title }}</a>
            <span class="ml-auto flex shrink-0 items-center gap-1.5 max-md:hidden">
              <span
                v-for="label in issue.labels"
                :key="label"
                class="flex h-5 items-center gap-1.5 rounded-full border border-edge px-2 text-[11.5px] text-muted"
              >
                <span class="size-[7px] rounded-full" :style="{ background: labelColors[label] }"></span>
                {{ label }}
              </span>
            </span>
            <span class="w-20 shrink-0 text-right text-xs text-faint max-md:hidden">{{ issue.when }}</span>
            <Avatar :person="issue.assignee" />
          </li>
        </ul>
      </div>
    </section>

    <div
      v-if="selected.length > 0"
      class="fixed bottom-6 left-1/2 z-40 flex -translate-x-1/2 items-center gap-2 rounded-xl border border-edge bg-panel px-3 py-2 shadow-2xl shadow-black/50"
    >
      <span class="px-1 text-fg-2">{{ selected.length }} selected</span>
      <ActionMenu :options="statusOptions" @select="moveSelected">
        <span class="hero-arrow-right-circle size-3.5 text-muted"></span>
        Move to…
      </ActionMenu>
      <button type="button" class="h-7 rounded-md px-2 text-[12.5px] text-muted hover:text-fg" @click="selected = []">
        Clear
      </button>
    </div>
  </div>
</template>
