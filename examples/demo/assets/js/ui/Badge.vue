<script setup lang="ts">
import { badge, type BadgeProps } from "./variants" with { type: "macro" }

const props = defineProps<{ tone?: BadgeProps["tone"] }>()
</script>

<template>
  <span :class="badge({ tone: props.tone })"><slot /></span>
</template>
