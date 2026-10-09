<script setup lang="ts">
import { TooltipProvider } from "reka-ui"

defineProps<{ delay: number }>()
</script>

<template>
  <TooltipProvider :delay-duration="delay"><p>Hi</p></TooltipProvider>
</template>
