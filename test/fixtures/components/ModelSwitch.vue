<script setup lang="ts">
import { SwitchRoot } from "reka-ui"

defineProps<{ id: string }>()
const checked = defineModel<boolean>({ default: false })
</script>

<template>
  <SwitchRoot :id="id" v-model="checked" />
</template>
