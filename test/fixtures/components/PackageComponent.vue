<script setup lang="ts">
import { DialogRoot } from "reka-ui"

defineProps<{ open: boolean }>()
</script>

<template>
  <DialogRoot :open="open"><p>Hi</p></DialogRoot>
</template>
