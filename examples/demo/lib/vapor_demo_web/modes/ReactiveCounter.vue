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
  <div class="space-y-6">
    <header>
      <h1 class="text-2xl font-bold tracking-tight text-zinc-900">Reactive</h1>
      <p class="text-sm text-zinc-500">
        This LiveView is this one .vue file. Its refs, computeds and handlers run on the server,
        and value-only updates are written straight to the DOM.
      </p>
    </header>
    <p class="font-mono text-4xl">{{ count }}</p>
    <p class="text-zinc-500">Doubled: {{ doubled }} · {{ label }}</p>
    <div class="flex gap-2">
      <button @click="decrement" class="rounded-md border border-zinc-300 px-4 py-2">−</button>
      <button @click="reset" class="rounded-md border border-zinc-300 px-4 py-2">Reset</button>
      <button @click="increment" class="rounded-md bg-zinc-900 px-4 py-2 text-white">+</button>
    </div>
  </div>
</template>
