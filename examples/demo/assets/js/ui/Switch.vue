<script setup lang="ts">
import { SwitchRoot, SwitchThumb } from "reka-ui"

defineProps<{ id: string }>()
const checked = defineModel<boolean>({ default: false })
</script>

<template>
  <SwitchRoot
    :id="id"
    v-model="checked"
    class="relative inline-flex h-5 w-9 shrink-0 cursor-pointer items-center rounded-full bg-zinc-300 transition-colors data-[state=checked]:bg-indigo-600"
  >
    <SwitchThumb class="block h-4 w-4 translate-x-0.5 rounded-full bg-white shadow transition-transform data-[state=checked]:translate-x-4" />
  </SwitchRoot>
</template>
