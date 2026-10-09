<script setup lang="ts">
import {
  DropdownMenuRoot, DropdownMenuTrigger, DropdownMenuPortal, DropdownMenuContent, DropdownMenuItem,
} from "reka-ui"

// A button that opens a menu of actions; picking one emits `select` with its
// value. The button's content is the slot.
defineProps<{ options: { value: string; label: string }[] }>()
const emit = defineEmits<{ select: [value: string] }>()
</script>

<template>
  <DropdownMenuRoot>
    <DropdownMenuTrigger
      class="flex h-7 items-center gap-1.5 rounded-md border border-edge bg-raised px-2.5 text-[12.5px] text-fg outline-none hover:bg-hover focus-visible:border-accent data-[state=open]:bg-hover"
    >
      <slot />
    </DropdownMenuTrigger>
    <DropdownMenuPortal>
      <DropdownMenuContent
        :side-offset="6"
        align="start"
        class="z-50 min-w-44 rounded-lg border border-edge bg-panel p-1 text-fg shadow-xl shadow-black/40"
      >
        <DropdownMenuItem
          v-for="option in options"
          :key="option.value"
          class="flex h-[30px] cursor-default items-center gap-2 rounded-md px-2 text-[13px] outline-none data-[highlighted]:bg-hover"
          @select="emit('select', option.value)"
        >{{ option.label }}</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenuPortal>
  </DropdownMenuRoot>
</template>
