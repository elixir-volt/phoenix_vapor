<script setup lang="ts">
import { button } from "./variants" with { type: "macro" }

const props = defineProps<{ variant?: "solid" | "ghost"; size?: "sm" | "md"; disabled?: boolean }>()
</script>

<template>
  <button type="button" :class="button({ variant: props.variant, size: props.size })" :disabled="props.disabled">
    <slot>Button</slot>
  </button>
</template>
