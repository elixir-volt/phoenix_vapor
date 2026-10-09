<script setup lang="ts">
// A person's initials on their colour, or a dashed ring for nobody.
defineProps<{ person: { name: string; initials: string; color: string } | null; size?: "sm" | "md" }>()
</script>

<template>
  <span
    v-if="person"
    :title="person.name"
    :style="{ background: person.color }"
    class="grid shrink-0 place-items-center rounded-full font-semibold text-[#0a0a0b]"
    :class="size === 'md' ? 'size-6 text-[10px]' : 'size-5 text-[9.5px]'"
  >{{ person.initials }}</span>
  <span
    v-else
    title="Unassigned"
    class="block shrink-0 rounded-full border border-dashed border-faint"
    :class="size === 'md' ? 'size-6' : 'size-5'"
  ></span>
</template>
