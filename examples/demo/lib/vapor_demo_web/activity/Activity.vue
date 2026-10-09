<script setup lang="ts">
// Rendered by the server alone: a function component the layout calls, with
// the entries as props. Every change in the tracker re-renders it over
// LiveView; no JavaScript of its own.
defineProps<{
  entries: { id: number; who: string; initials: string; color: string; what: string; when: string }[]
}>()
</script>

<template>
  <aside
    aria-label="Activity"
    data-render="server"
    data-render-label="server-only .vue"
    class="sticky top-0 flex h-screen w-60 shrink-0 flex-col gap-3.5 overflow-y-auto border-l border-line px-4 py-4 max-xl:hidden"
  >
    <div class="flex items-center gap-2">
      <span class="font-medium">Activity</span>
      <span class="size-1.5 rounded-full bg-[#3dd68c]"></span>
      <span class="text-xs text-faint">live</span>
    </div>
    <ol class="flex flex-col gap-3.5">
      <li v-for="entry in entries" :key="entry.id" class="flex gap-2.5">
        <span
          class="grid size-5 shrink-0 place-items-center rounded-full text-[9.5px] font-semibold text-[#0a0a0b]"
          :style="{ background: entry.color }"
        >{{ entry.initials }}</span>
        <div class="flex min-w-0 flex-col gap-0.5">
          <span class="text-[12.5px] text-fg-2"><span class="font-medium text-fg">{{ entry.who }}</span> {{ entry.what }}</span>
          <span class="text-[11.5px] text-faint">{{ entry.when }}</span>
        </div>
      </li>
    </ol>
  </aside>
</template>
