<script setup>
import { ref, computed } from "vue"

const count = ref(0)
const doubled = computed(() => count * 2)
const label = computed(() => count === 0 ? "Zero" : count > 0 ? "Positive" : "Negative")

function increment() {
  count++
}

function decrement() {
  count--
}

function reset() {
  count = 0
}
</script>

<template>
  <div class="space-y-4">
    <h2 class="text-2xl font-bold">Reactive Counter (.vue SFC)</h2>
    <p class="text-4xl font-mono">{{ count }}</p>
    <p class="text-lg text-gray-500">Doubled: {{ doubled }} · {{ label }}</p>
    <div class="flex gap-2">
      <button @click="decrement" class="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600">-</button>
      <button @click="reset" class="px-4 py-2 bg-gray-500 text-white rounded hover:bg-gray-600">Reset</button>
      <button @click="increment" class="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600">+</button>
    </div>
    <p class="text-xs text-gray-400">This entire LiveView is defined in a single .vue file — no Elixir code needed.</p>
  </div>
</template>
