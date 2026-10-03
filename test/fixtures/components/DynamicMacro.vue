<script setup lang="ts">
import Button from "./Button.vue"

defineProps<{ variant: string }>()
</script>

<template>
  <Button :variant="variant">Go</Button>
</template>
