<script setup lang="ts">
import {
  DropdownMenuRoot, DropdownMenuTrigger, DropdownMenuPortal, DropdownMenuContent,
  DropdownMenuRadioGroup, DropdownMenuRadioItem, DropdownMenuItemIndicator,
} from "reka-ui"

// A filter chip with a menu of its values. `current` is the chosen value's
// label, passed in so the server's render shows it too; the values are
// whatever the parent's model can hold, and the menu folds once for each.
defineProps<{ label: string; options: { value: string; label: string }[]; current: string }>()
const model = defineModel<string>({ required: true })
</script>

<template>
  <DropdownMenuRoot>
    <DropdownMenuTrigger
      class="flex h-[26px] items-center gap-1.5 rounded-md border border-dashed border-edge px-2.5 text-[12.5px] text-muted outline-none hover:text-fg-2 focus-visible:border-accent data-[state=open]:bg-raised"
    >
      {{ label }}: <span class="text-fg">{{ current }}</span>
    </DropdownMenuTrigger>
    <DropdownMenuPortal>
      <DropdownMenuContent
        :side-offset="6"
        align="start"
        class="z-50 min-w-44 rounded-lg border border-edge bg-panel p-1 text-fg shadow-xl shadow-black/40"
      >
        <DropdownMenuRadioGroup v-model="model">
          <DropdownMenuRadioItem
            v-for="option in options"
            :key="option.value"
            :value="option.value"
            class="flex h-[30px] cursor-default items-center gap-2 rounded-md px-2 text-[13px] outline-none data-[highlighted]:bg-hover"
          >
            {{ option.label }}
            <DropdownMenuItemIndicator class="ml-auto text-accent">
              <span class="hero-check size-3.5"></span>
            </DropdownMenuItemIndicator>
          </DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenuPortal>
  </DropdownMenuRoot>
</template>
