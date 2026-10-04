<script setup lang="ts">
import { TooltipProvider } from "reka-ui"

defineProps<{ name: string }>()
</script>

<template>
  <TooltipProvider :delay-duration="300"><p>Hello {{ name }}</p></TooltipProvider>
</template>
