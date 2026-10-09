<script setup lang="ts">
import { button, type ButtonProps } from "./variants" with { type: "macro" }

const props = defineProps<{
  variant?: ButtonProps["variant"]
  size?: ButtonProps["size"]
  type?: "button" | "submit"
  disabled?: boolean
}>()
</script>

<template>
  <button
    :type="props.type ?? 'button'"
    :class="button({ variant: props.variant, size: props.size })"
    :disabled="props.disabled"
  >
    <slot />
  </button>
</template>
