<script setup lang="ts">
import {
  SelectRoot, SelectTrigger, SelectValue, SelectIcon, SelectPortal,
  SelectContent, SelectViewport, SelectItem, SelectItemText,
} from "reka-ui"

// `label` is the selected option's, which SelectValue otherwise reads from the
// items once they mount in the browser, so the server's render shows it too.
defineProps<{ options: { value: string; label: string }[]; placeholder?: string; label?: string }>()
const model = defineModel<string>()
</script>

<template>
  <SelectRoot v-model="model">
    <SelectTrigger class="inline-flex h-9 min-w-40 items-center justify-between gap-2 rounded-md border border-zinc-300 bg-white px-3 text-sm">
      <SelectValue :placeholder="placeholder">{{ label ?? placeholder }}</SelectValue>
      <SelectIcon class="text-zinc-400">▾</SelectIcon>
    </SelectTrigger>
    <SelectPortal>
      <SelectContent position="popper" :side-offset="4" class="z-50 min-w-40 rounded-md border border-zinc-200 bg-white p-1 shadow-md">
        <SelectViewport>
          <SelectItem
            v-for="option in options"
            :key="option.value"
            :value="option.value"
            class="cursor-pointer rounded px-2 py-1.5 text-sm outline-none data-[highlighted]:bg-zinc-100"
          >
            <SelectItemText>{{ option.label }}</SelectItemText>
          </SelectItem>
        </SelectViewport>
      </SelectContent>
    </SelectPortal>
  </SelectRoot>
</template>
