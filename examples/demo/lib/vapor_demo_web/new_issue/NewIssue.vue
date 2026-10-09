<script setup>
// Reactive mode: this script runs on the server, in QuickBEAM, with Vue's
// own reactivity. Refs are read by name, without .value. The form's changes
// arrive as `edit` events, and the computeds follow, as they would in the
// browser; no Vue reaches the browser.
import { ref, computed } from "vue"

const title = ref("")
const description = ref("")
const team = ref("engineering")
const priority = ref("none")

const length = computed(() => title.length)
const tooLong = computed(() => title.length > 80)
const ready = computed(() => title.trim().length > 0 && title.length <= 80)

// The branch this issue would get, as the issue page shows it.
const branch = computed(() => {
  const words = title
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(" ")
    .filter((word) => word)
    .slice(0, 5)
  const prefix = team === "design" ? "des" : "eng"
  return "alice/" + prefix + "-new" + (words.length ? "-" + words.join("-") : "")
})

function edit() {
  title = __params.title ?? title
  description = __params.description ?? description
  team = __params.team ?? team
  priority = __params.priority ?? priority
}
</script>

<template>
  <div class="flex min-h-0 flex-1 flex-col">
    <header class="flex items-center gap-2 border-b border-line px-5 py-3 text-[13.5px]">
      <span class="text-muted">Issues</span>
      <span class="text-faint">/</span>
      <span class="font-medium">New issue</span>
    </header>

    <section
      data-render="reactive"
      data-render-label="reactive · Vue's reactivity on the server"
      data-render-source="lib/vapor_demo_web/new_issue/NewIssue.vue"
      class="flex-1"
    >
      <form phx-change="edit" phx-submit="create" class="mx-auto flex max-w-2xl flex-col gap-5 px-6 py-10">
        <fieldset class="flex flex-col gap-2">
          <legend class="mb-2 text-xs text-faint">Team</legend>
          <div class="flex gap-2">
            <label
              class="flex h-8 cursor-pointer items-center gap-2 rounded-md border px-3"
              :class="team === 'engineering' ? 'border-accent bg-accent-soft text-fg' : 'border-edge text-muted'"
            >
              <input type="radio" name="team" value="engineering" :checked="team === 'engineering'" class="sr-only" />
              Engineering
            </label>
            <label
              class="flex h-8 cursor-pointer items-center gap-2 rounded-md border px-3"
              :class="team === 'design' ? 'border-accent bg-accent-soft text-fg' : 'border-edge text-muted'"
            >
              <input type="radio" name="team" value="design" :checked="team === 'design'" class="sr-only" />
              Design
            </label>
          </div>
        </fieldset>

        <div class="flex flex-col gap-1.5">
          <label for="new-title" class="text-xs text-faint">Title</label>
          <input
            id="new-title"
            name="title"
            :value="title"
            autocomplete="off"
            placeholder="What needs doing?"
            phx-debounce="100"
            class="h-11 rounded-lg border border-edge bg-panel px-3 text-[17px] font-medium text-fg outline-none placeholder:text-faint focus:border-faint"
          />
          <div class="flex justify-between text-xs">
            <span v-if="tooLong" class="text-[#f2555a]">Keep it under 80 characters.</span>
            <span v-else class="text-faint">A short sentence; the description holds the rest.</span>
            <span :class="tooLong ? 'text-[#f2555a]' : 'text-faint'">{{ length }}/80</span>
          </div>
        </div>

        <div class="flex flex-col gap-1.5">
          <label for="new-description" class="text-xs text-faint">Description</label>
          <textarea
            id="new-description"
            name="description"
            rows="5"
            placeholder="Add a description…"
            phx-debounce="200"
            class="field-sizing-content min-h-28 resize-none rounded-lg border border-edge bg-panel px-3 py-2.5 text-[14px] leading-relaxed text-fg-2 outline-none placeholder:text-faint focus:border-faint"
          >{{ description }}</textarea>
        </div>

        <fieldset class="flex flex-col gap-2">
          <legend class="mb-2 text-xs text-faint">Priority</legend>
          <div class="flex flex-wrap gap-2">
            <label
              v-for="option in [['urgent', 'Urgent'], ['high', 'High'], ['medium', 'Medium'], ['low', 'Low'], ['none', 'None']]"
              :key="option[0]"
              class="flex h-8 cursor-pointer items-center rounded-md border px-3"
              :class="priority === option[0] ? 'border-accent bg-accent-soft text-fg' : 'border-edge text-muted'"
            >
              <input type="radio" name="priority" :value="option[0]" :checked="priority === option[0]" class="sr-only" />
              {{ option[1] }}
            </label>
          </div>
        </fieldset>

        <div class="flex flex-wrap items-center gap-3 border-t border-line pt-5">
          <span class="text-xs text-faint">Branch</span>
          <code class="font-mono text-xs text-link">{{ branch }}</code>
          <!-- A plain button, not a component: its disabled state is then a
               value the server writes straight to the DOM. -->
          <button
            type="submit"
            :disabled="!ready"
            class="ml-auto h-8 rounded-md bg-accent px-4 font-medium text-accent-fg hover:opacity-90 disabled:opacity-40"
          >Create issue</button>
        </div>
      </form>
    </section>
  </div>
</template>
