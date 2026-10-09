<script setup lang="ts">
import { ref, computed, watch, useTemplateRef } from "vue"
import { onKeyStroke, useEventListener } from "@vueuse/core"
import { DialogRoot, DialogPortal, DialogOverlay, DialogContent, DialogTitle } from "reka-ui"
import StatusIcon from "@/ui/StatusIcon.vue"

type Item = { key: string; title: string; status: string }
type Team = { key: string; name: string }

// Every issue, kept current by the server, and the teams, for jumping to.
const props = defineProps<{ issues: Item[]; teams: Team[] }>()

// Typed as its values, so the server folds the dialog open and closed.
const open = ref<boolean>(false)
const query = ref("")
const active = ref(0)
const list = useTemplateRef<HTMLElement>("list")

onKeyStroke("k", (event) => {
  if (!event.metaKey && !event.ctrlKey) return
  event.preventDefault()
  open.value = !open.value
})

// The sidebar's search button asks for it.
useEventListener(window, "palette:open", () => {
  open.value = true
})

const commands = computed(() => {
  const term = query.value.trim().toLowerCase()

  const pages = [
    { id: "new", label: "Create a new issue", href: "/new", hint: "Action", status: "" },
    { id: "mine", label: "Go to my issues", href: "/my-issues", hint: "Page", status: "" },
    ...props.teams.flatMap((team) => [
      { id: `${team.key}-board`, label: `Go to ${team.name} board`, href: `/${team.key}/board`, hint: "Page", status: "" },
      { id: `${team.key}-issues`, label: `Go to ${team.name} issues`, href: `/${team.key}/issues`, hint: "Page", status: "" },
    ]),
  ]

  const issues = props.issues.map((issue) => ({
    id: issue.key,
    label: issue.title,
    href: `/issue/${issue.key}`,
    hint: issue.key,
    status: issue.status,
  }))

  return [...pages, ...issues]
    .filter((command) => !term || `${command.label} ${command.hint}`.toLowerCase().includes(term))
    .slice(0, 8)
})

watch(query, () => {
  active.value = 0
})

watch(open, (isOpen) => {
  if (!isOpen) query.value = ""
})

function move(step: number) {
  const count = commands.value.length
  if (count > 0) active.value = (active.value + step + count) % count
}

function choose() {
  list.value?.querySelectorAll("a")[active.value]?.click()
}
</script>

<script lang="elixir">
# The commands for the server's render of the open palette, as a replay
# shows it: the same filter over pages and issues, at most eight.
def commands(%{issues: issues, teams: teams, query: query}) do
  term = query |> String.trim() |> String.downcase()

  pages =
    [
      %{id: "new", label: "Create a new issue", href: "/new", hint: "Action", status: ""},
      %{id: "mine", label: "Go to my issues", href: "/my-issues", hint: "Page", status: ""}
    ] ++
      Enum.flat_map(teams, fn team ->
        [
          %{id: "#{team.key}-board", label: "Go to #{team.name} board", href: "/#{team.key}/board", hint: "Page", status: ""},
          %{id: "#{team.key}-issues", label: "Go to #{team.name} issues", href: "/#{team.key}/issues", hint: "Page", status: ""}
        ]
      end)

  items =
    Enum.map(issues, fn issue ->
      %{id: issue.key, label: issue.title, href: "/issue/#{issue.key}", hint: issue.key, status: issue.status}
    end)

  (pages ++ items)
  |> Enum.filter(&(term == "" or String.contains?(String.downcase("#{&1.label} #{&1.hint}"), term)))
  |> Enum.take(8)
end
</script>

<template>
  <DialogRoot v-model:open="open">
    <DialogPortal>
      <DialogOverlay class="fixed inset-0 z-50 bg-black/60 backdrop-blur-[1px]" />
      <DialogContent
        data-render="folded"
        data-render-label="folded · Reka Dialog, open and closed"
        data-render-source="lib/vapor_demo_web/palette/Palette.vue"
        class="fixed left-1/2 top-[14vh] z-50 w-[560px] max-w-[calc(100vw-32px)] -translate-x-1/2 overflow-hidden rounded-xl border border-edge bg-panel text-[13px] text-fg shadow-2xl shadow-black/60 outline-none"
        @keydown.down.prevent="move(1)"
        @keydown.up.prevent="move(-1)"
        @keydown.enter.prevent="choose"
      >
        <DialogTitle class="sr-only">Command palette</DialogTitle>
        <input
          v-model="query"
          aria-label="Search commands and issues"
          placeholder="Type a command or search issues…"
          class="h-12 w-full border-b border-edge bg-transparent px-4 text-[15px] outline-none placeholder:text-faint"
        />
        <div ref="list" class="max-h-80 overflow-y-auto p-1.5">
          <a
            v-for="(command, index) in commands"
            :key="command.id"
            :href="command.href"
            data-phx-link="redirect"
            data-phx-link-state="push"
            class="flex h-9 items-center gap-2.5 rounded-md px-2.5"
            :class="index === active ? 'bg-hover text-fg' : 'text-fg-2'"
            @mousemove="active = index"
            @click="open = false"
          >
            <StatusIcon v-if="command.status" :status="command.status" />
            <span v-else class="hero-arrow-right size-3.5 text-muted"></span>
            <span class="truncate">{{ command.label }}</span>
            <span class="ml-auto shrink-0 font-mono text-[11px] text-faint">{{ command.hint }}</span>
          </a>
          <p v-if="commands.length === 0" class="px-3 py-6 text-center text-faint">No results</p>
        </div>
        <div class="flex items-center gap-3 border-t border-line px-3 py-2 text-[11.5px] text-faint">
          <span><kbd class="font-mono">↑↓</kbd> to move</span>
          <span><kbd class="font-mono">↵</kbd> to open</span>
          <span class="ml-auto"><kbd class="font-mono">esc</kbd> to close</span>
        </div>
      </DialogContent>
    </DialogPortal>
  </DialogRoot>
</template>
