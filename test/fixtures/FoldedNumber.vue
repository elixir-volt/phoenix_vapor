<script setup lang="ts">
import { ref } from "vue"
import { ProgressRoot, ProgressIndicator } from "reka-ui"

const step = ref<0 | 50 | 100>(0)
</script>

<template>
  <ProgressRoot :model-value="step"><ProgressIndicator /></ProgressRoot>
</template>
