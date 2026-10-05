<script setup>
import { ref, computed } from "vue"
const count = ref(0)
const render = computed(() => count.value)
</script>

<script lang="elixir">
def render(assigns), do: assigns.count
</script>

<template>
  <p>{{ render }}</p>
</template>
