<script setup lang="ts">
import {
  DropdownMenuRoot, DropdownMenuTrigger, DropdownMenuPortal, DropdownMenuContent, DropdownMenuItem,
} from "reka-ui"

// A property row whose value opens a menu of the others. The row shows the
// current value as its slot, so the server's render has it; picking one
// emits `select` with the option's value.
defineProps<{ label: string; options: { value: string; label: string }[]; value: string }>()
const emit = defineEmits<{ select: [value: string] }>()
</script>

<template>
  <DropdownMenuRoot>
    <DropdownMenuTrigger
      class="flex h-8 w-full items-center gap-2 rounded-md px-2 text-left outline-none hover:bg-raised focus-visible:bg-raised data-[state=open]:bg-raised"
    >
      <span class="w-[76px] shrink-0 text-muted">{{ label }}</span>
      <slot />
    </DropdownMenuTrigger>
    <DropdownMenuPortal>
      <DropdownMenuContent
        :side-offset="4"
        align="start"
        class="z-50 min-w-48 rounded-lg border border-edge bg-panel p-1 text-fg shadow-xl shadow-black/40"
      >
        <DropdownMenuItem
          v-for="option in options"
          :key="option.value"
          class="flex h-[30px] cursor-default items-center gap-2 rounded-md px-2 text-[13px] outline-none data-[highlighted]:bg-hover"
          @select="emit('select', option.value)"
        >
          {{ option.label }}
          <span v-if="option.value === value" class="hero-check ml-auto size-3.5 text-accent"></span>
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenuPortal>
  </DropdownMenuRoot>
</template>
