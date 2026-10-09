<script setup lang="ts">
import { ref, computed } from "vue"
import FilterMenu from "@/ui/FilterMenu.vue"
import StatusIcon from "@/ui/StatusIcon.vue"
import PriorityIcon from "@/ui/PriorityIcon.vue"
import Avatar from "@/ui/Avatar.vue"

type Status = "backlog" | "todo" | "in_progress" | "in_review" | "done"
type Priority = "none" | "low" | "medium" | "high" | "urgent"
type Person = { id: number; name: string; initials: string; color: string }
type Issue = {
  id: number
  key: string
  title: string
  status: Status
  priority: Priority
  assignee_id: number | null
  labels: string[]
}

// The server owns the issues; moving one goes through a server action, and
// every open board follows.
const issues = defineModel<Issue[]>("issues", { required: true })
const props = defineProps<{ team: { key: string; name: string }; people: Person[]; me: number }>()

// The filters and the drag are the browser's. Typed as their values, so the
// server folds the filter menus once for each, and a replay shows them.
const assignee = ref<"anyone" | "me" | "unassigned">("anyone")
const priority = ref<"all" | "urgent" | "high" | "medium" | "low">("all")
const dragging = ref<number | null>(null)
const over = ref<Status | null>(null)

const statuses = [
  { status: "backlog", label: "Backlog" },
  { status: "todo", label: "Todo" },
  { status: "in_progress", label: "In Progress" },
  { status: "in_review", label: "In Review" },
  { status: "done", label: "Done" },
]

const assigneeOptions = [
  { value: "anyone", label: "Anyone" },
  { value: "me", label: "Me" },
  { value: "unassigned", label: "Unassigned" },
]
const assigneeLabels: Record<string, string> = { anyone: "Anyone", me: "Me", unassigned: "Unassigned" }

const priorityOptions = [
  { value: "all", label: "All" },
  { value: "urgent", label: "Urgent" },
  { value: "high", label: "High" },
  { value: "medium", label: "Medium" },
  { value: "low", label: "Low" },
]
const priorityLabels: Record<string, string> = { all: "All", urgent: "Urgent", high: "High", medium: "Medium", low: "Low" }

const labelColors: Record<string, string> = {
  Bug: "#f2555a",
  Auth: "#f5a524",
  API: "#4c9bff",
  UI: "#b48cff",
  Realtime: "#3dd68c",
}

const columns = computed(() => {
  const visible = issues.value.filter(
    (issue) =>
      (assignee.value === "anyone" ||
        (assignee.value === "me" && issue.assignee_id === props.me) ||
        (assignee.value === "unassigned" && issue.assignee_id === null)) &&
      (priority.value === "all" || issue.priority === priority.value),
  )

  return statuses.map((column) => ({
    ...column,
    issues: visible
      .filter((issue) => issue.status === column.status)
      .map((issue) => ({ ...issue, assignee: props.people.find((p) => p.id === issue.assignee_id) ?? null })),
  }))
})

function moveIssue(id: number, status: Status) {
  "use server"
  issues.value = issues.value.map((issue) => (issue.id === id ? { ...issue, status } : issue))
}

function drop(status: Status) {
  const id = dragging.value
  dragging.value = null
  over.value = null
  const issue = issues.value.find((i) => i.id === id)
  if (issue && issue.status !== status) moveIssue(issue.id, status)
}
</script>

<script lang="elixir">
# The board's columns for the server's render, the first paint and a session
# replay: the issues the filters let through, by status, with their assignee.
def columns(%{issues: issues, people: people, me: me, assignee: assignee, priority: priority}) do
  visible =
    Enum.filter(issues, fn issue ->
      assignee_ok =
        case assignee do
          "me" -> issue.assignee_id == me
          "unassigned" -> is_nil(issue.assignee_id)
          _anyone -> true
        end

      assignee_ok and (priority == "all" or issue.priority == priority)
    end)

  for {status, label} <- [
        {"backlog", "Backlog"},
        {"todo", "Todo"},
        {"in_progress", "In Progress"},
        {"in_review", "In Review"},
        {"done", "Done"}
      ] do
    %{
      status: status,
      label: label,
      issues:
        for issue <- visible, issue.status == status do
          Map.put(issue, :assignee, Enum.find(people, &(&1.id == issue.assignee_id)))
        end
    }
  end
end
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <header class="flex flex-wrap items-center gap-3 border-b border-line px-5 py-2.5">
      <div class="flex items-center gap-2 text-[13.5px]">
        <span class="text-muted">{{ team.name }}</span>
        <span class="text-faint">/</span>
        <span class="font-medium">Board</span>
      </div>
      <div
        data-render="folded"
        data-render-label="folded · Reka menus"
        data-render-tag="below"
        class="ml-2 flex flex-wrap gap-1.5 p-1"
      >
        <FilterMenu v-model="assignee" label="Assignee" :options="assigneeOptions" :current="assigneeLabels[assignee]" />
        <FilterMenu v-model="priority" label="Priority" :options="priorityOptions" :current="priorityLabels[priority]" />
      </div>
      <div class="ml-auto flex items-center gap-2">
        <nav aria-label="View" class="flex overflow-hidden rounded-md border border-edge">
          <span class="flex h-7 items-center bg-raised px-2.5 text-[12.5px] text-fg">Board</span>
          <a
            :href="`/${team.key}/issues`"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="flex h-7 items-center px-2.5 text-[12.5px] text-muted hover:text-fg"
          >List</a>
        </nav>
        <a
          href="/new"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="flex h-[30px] items-center gap-1.5 rounded-md bg-accent px-3 font-medium text-accent-fg hover:opacity-90"
        >
          <span class="hero-plus size-3.5"></span>
          New issue
        </a>
      </div>
    </header>

    <section
      data-render="hybrid"
      data-render-label="hybrid · Vue in the browser"
      class="min-h-0 flex-1 overflow-x-auto px-5 pb-8 pt-4"
    >
      <div class="grid min-w-[880px] grid-cols-5 gap-3">
        <div
          v-for="column in columns"
          :key="column.status"
          class="flex min-w-0 flex-col gap-2 rounded-lg p-1 transition-colors"
          :class="over === column.status ? 'bg-raised' : ''"
          @dragover.prevent="over = column.status"
          @drop.prevent="drop(column.status)"
        >
          <div class="flex h-[30px] items-center gap-2 px-1">
            <StatusIcon :status="column.status" />
            <span class="font-medium">{{ column.label }}</span>
            <span class="text-faint">{{ column.issues.length }}</span>
          </div>

          <article
            v-for="issue in column.issues"
            :key="issue.id"
            draggable="true"
            class="flex cursor-grab flex-col gap-2 rounded-[9px] border border-line bg-panel px-3 py-2.5 hover:border-edge active:cursor-grabbing"
            :class="dragging === issue.id ? 'opacity-40' : ''"
            @dragstart="dragging = issue.id"
            @dragend="dragging = null"
          >
            <div class="flex items-center gap-2">
              <span class="font-mono text-[11.5px] text-faint">{{ issue.key }}</span>
              <span class="ml-auto"><Avatar :person="issue.assignee" /></span>
            </div>
            <a
              :href="`/issue/${issue.key}`"
              data-phx-link="redirect"
              data-phx-link-state="push"
              draggable="false"
              class="leading-snug text-fg-2 hover:text-fg"
            >{{ issue.title }}</a>
            <div class="flex flex-wrap items-center gap-1.5">
              <PriorityIcon :priority="issue.priority" />
              <span
                v-for="label in issue.labels"
                :key="label"
                class="flex h-5 items-center gap-1.5 rounded-full border border-edge px-2 text-[11.5px] text-muted"
              >
                <span class="size-[7px] rounded-full" :style="{ background: labelColors[label] }"></span>
                {{ label }}
              </span>
            </div>
          </article>

          <p
            v-if="column.issues.length === 0"
            class="rounded-lg border border-dashed border-line px-3 py-6 text-center text-faint"
          >No issues</p>
        </div>
      </div>
    </section>
  </div>
</template>
