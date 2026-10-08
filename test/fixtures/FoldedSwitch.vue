<script setup>
import { ref } from "vue"
import { SwitchRoot, SwitchThumb } from "reka-ui"

// Inferred as boolean.
const notify = ref(false)
</script>

<template>
  <label>Notify <SwitchRoot v-model="notify"><SwitchThumb /></SwitchRoot></label>
</template>
