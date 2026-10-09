<script setup lang="ts">
import { ref, computed } from "vue"
import PropertyMenu from "@/ui/PropertyMenu.vue"
import StatusIcon from "@/ui/StatusIcon.vue"
import PriorityIcon from "@/ui/PriorityIcon.vue"
import Avatar from "@/ui/Avatar.vue"

type Person = { id: number; name: string; initials: string; color: string }
type Issue = {
  id: number
  key: string
  title: string
  description: string
  status: string
  priority: string
  assignee_id: number | null
  labels: string[]
}
type Comment = { id: number; author: Person; body: string; when: string }

// The server owns the issue and its comments. Edits show at once and go
// through server actions; every open page follows.
const issue = defineModel<Issue>("issue", { required: true })
const comments = defineModel<Comment[]>("comments", { required: true })
const props = defineProps<{ team: { key: string; name: string }; people: Person[]; me: Person }>()

// What's typed and not yet saved: null while the field shows the issue's.
const titleDraft = ref<string | null>(null)
const descriptionDraft = ref<string | null>(null)
const commentDraft = ref("")

const statusOptions = [
  { value: "backlog", label: "Backlog" },
  { value: "todo", label: "Todo" },
  { value: "in_progress", label: "In Progress" },
  { value: "in_review", label: "In Review" },
  { value: "done", label: "Done" },
]
const statusLabels: Record<string, string> = {
  backlog: "Backlog",
  todo: "Todo",
  in_progress: "In Progress",
  in_review: "In Review",
  done: "Done",
}
const priorityOptions = [
  { value: "urgent", label: "Urgent" },
  { value: "high", label: "High" },
  { value: "medium", label: "Medium" },
  { value: "low", label: "Low" },
  { value: "none", label: "No priority" },
]
const priorityLabels: Record<string, string> = {
  urgent: "Urgent",
  high: "High",
  medium: "Medium",
  low: "Low",
  none: "No priority",
}
const labelColors: Record<string, string> = {
  Bug: "#f2555a",
  Auth: "#f5a524",
  API: "#4c9bff",
  UI: "#b48cff",
  Realtime: "#3dd68c",
}

const assignee = computed(() => props.people.find((p) => p.id === issue.value.assignee_id) ?? null)

const assigneeOptions = computed(() => [
  ...props.people.map((p) => ({ value: String(p.id), label: p.name })),
  { value: "none", label: "Unassigned" },
])

const assigneeValue = computed(() =>
  issue.value.assignee_id === null ? "none" : String(issue.value.assignee_id),
)

// The branch to work on it in, as Linear suggests one.
const branch = computed(() => {
  const words = issue.value.title.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().split(" ").slice(0, 5)
  return `${props.me.name.split(" ")[0].toLowerCase()}/${issue.value.key.toLowerCase()}-${words.join("-")}`
})

function editIssue(title: string, description: string) {
  "use server"
  issue.value = { ...issue.value, title, description }
}

function setStatus(status: string) {
  "use server"
  issue.value = { ...issue.value, status }
}

function setPriority(priority: string) {
  "use server"
  issue.value = { ...issue.value, priority }
}

function setAssignee(assignee: string) {
  "use server"
  issue.value = { ...issue.value, assignee_id: assignee === "none" ? null : Number(assignee) }
}

function addComment(body: string) {
  "use server"
  comments.value = [...comments.value, { id: -Date.now(), author: props.me, body, when: "just now" }]
}

function save() {
  const title = (titleDraft.value ?? issue.value.title).trim()
  const description = descriptionDraft.value ?? issue.value.description
  titleDraft.value = null
  descriptionDraft.value = null
  if (title && (title !== issue.value.title || description !== issue.value.description)) {
    editIssue(title, description)
  }
}

function submitComment() {
  const body = commentDraft.value.trim()
  if (!body) return
  commentDraft.value = ""
  addComment(body)
}
</script>

<script lang="elixir">
# The computeds the server renders with: who the issue is assigned to, the
# assignee menu's value and options, and the branch name.
def assignee(%{issue: issue, people: people}),
  do: Enum.find(people, &(&1.id == issue.assignee_id))

def assignee_value(%{issue: %{assignee_id: nil}}), do: "none"
def assignee_value(%{issue: %{assignee_id: id}}), do: to_string(id)

def assignee_options(%{people: people}),
  do: Enum.map(people, &%{value: to_string(&1.id), label: &1.name}) ++ [%{value: "none", label: "Unassigned"}]

def branch(%{issue: issue, me: me}) do
  words =
    issue.title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.split()
    |> Enum.take(5)

  first = me.name |> String.split() |> hd() |> String.downcase()
  "#{first}/#{String.downcase(issue.key)}-#{Enum.join(words, "-")}"
end
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <header class="flex items-center gap-2 border-b border-line px-5 py-3 text-[13.5px]">
      <a
        :href="`/${team.key}/board`"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="text-muted hover:text-fg"
      >{{ team.name }}</a>
      <span class="text-faint">/</span>
      <span class="font-mono text-[13px]">{{ issue.key }}</span>
    </header>

    <div class="flex min-h-0 flex-1 flex-wrap">
      <section
        data-render="hybrid"
        data-render-label="hybrid · edits in the browser, saved by the server"
        class="min-w-0 flex-[999_1_480px]"
      >
        <div class="mx-auto flex max-w-3xl flex-col gap-4 px-6 py-8 md:px-12">
          <label for="issue-title" class="sr-only">Title</label>
          <input
            id="issue-title"
            :value="titleDraft ?? issue.title"
            class="bg-transparent text-2xl font-semibold tracking-tight text-fg outline-none"
            @input="titleDraft = ($event.target as HTMLInputElement).value"
            @keydown.enter.prevent="save"
            @blur="save"
          />
          <label for="issue-description" class="sr-only">Description</label>
          <textarea
            id="issue-description"
            :value="descriptionDraft ?? issue.description"
            rows="3"
            placeholder="Add a description…"
            class="field-sizing-content min-h-16 resize-none bg-transparent text-[14px] leading-relaxed text-fg-2 outline-none placeholder:text-faint"
            @input="descriptionDraft = ($event.target as HTMLTextAreaElement).value"
            @blur="save"
          ></textarea>

          <div class="my-2 h-px bg-line"></div>
          <h2 class="font-medium">Comments</h2>
          <p v-if="comments.length === 0" class="text-faint">No comments yet.</p>
          <article v-for="comment in comments" :key="comment.id" class="flex gap-2.5">
            <Avatar :person="comment.author" size="md" />
            <div class="flex min-w-0 flex-col gap-1 rounded-[9px] border border-line bg-panel px-3 py-2.5">
              <span>
                <span class="font-medium">{{ comment.author.name }}</span>
                <span class="text-xs text-faint"> · {{ comment.when }}</span>
              </span>
              <p class="whitespace-pre-line text-fg-2">{{ comment.body }}</p>
            </div>
          </article>

          <form
            class="flex flex-col gap-2 rounded-[9px] border border-edge bg-panel px-3 py-2.5 focus-within:border-faint"
            @submit.prevent="submitComment"
          >
            <label for="comment" class="sr-only">Comment</label>
            <textarea
              id="comment"
              v-model="commentDraft"
              rows="2"
              placeholder="Leave a comment…"
              class="field-sizing-content min-h-10 resize-none bg-transparent text-fg outline-none placeholder:text-faint"
              @keydown.meta.enter.prevent="submitComment"
            ></textarea>
            <div class="flex items-center justify-between">
              <span class="text-xs text-faint">⌘↵ to send</span>
              <button
                type="submit"
                :disabled="commentDraft.trim() === ''"
                class="h-7 rounded-md border border-edge bg-raised px-3 text-[12.5px] text-fg hover:bg-hover disabled:opacity-40"
              >Comment</button>
            </div>
          </form>
        </div>
      </section>

      <aside
        aria-label="Properties"
        data-render="folded"
        data-render-label="folded · Reka menus"
        class="flex flex-[1_1_260px] flex-col gap-0.5 border-l border-line px-3 py-5 md:max-w-72"
      >
        <span class="px-2 pb-2 text-xs text-faint">Properties</span>
        <PropertyMenu label="Status" :options="statusOptions" :value="issue.status" @select="setStatus">
          <StatusIcon :status="issue.status" />
          {{ statusLabels[issue.status] }}
        </PropertyMenu>
        <PropertyMenu label="Priority" :options="priorityOptions" :value="issue.priority" @select="setPriority">
          <PriorityIcon :priority="issue.priority" />
          {{ priorityLabels[issue.priority] }}
        </PropertyMenu>
        <PropertyMenu label="Assignee" :options="assigneeOptions" :value="assigneeValue" @select="setAssignee">
          <Avatar :person="assignee" />
          {{ assignee ? assignee.name : "Unassigned" }}
        </PropertyMenu>
        <div class="flex min-h-8 items-center gap-2 px-2">
          <span class="w-[76px] shrink-0 text-muted">Labels</span>
          <span v-if="issue.labels.length === 0" class="text-faint">None</span>
          <span class="flex flex-wrap gap-1.5">
            <span
              v-for="label in issue.labels"
              :key="label"
              class="flex h-5 items-center gap-1.5 rounded-full border border-edge px-2 text-[11.5px] text-muted"
            >
              <span class="size-[7px] rounded-full" :style="{ background: labelColors[label] }"></span>
              {{ label }}
            </span>
          </span>
        </div>
        <div class="mx-2 my-3 h-px bg-line"></div>
        <span class="px-2 text-xs text-faint">Branch</span>
        <code class="break-all px-2 py-1 font-mono text-xs text-link">{{ branch }}</code>
      </aside>
    </div>
  </div>
</template>
