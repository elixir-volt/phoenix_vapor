<script setup lang="ts">
import { ref } from "vue"
import Button from "@/ui/Button.vue"

// The server's: saving changes it, and the server may decline.
const saved = defineModel<number>("saved", { required: true })

// The browser's: counting never reaches the server.
const count = ref(0)

function save(count: number) {
  "use server"
  // Nothing to save: the action never leaves the browser.
  if (count === saved.value) return
  // Shown at once; the server's answer replaces it.
  saved.value = count
}
</script>

<template>
  <div class="space-y-6">
    <header>
      <h1 class="text-2xl font-bold tracking-tight text-zinc-900">Hybrid</h1>
      <p class="text-sm text-zinc-500">
        Vue runs this component in the browser; the server renders its first paint and owns the saved
        count, a model. Counting is instant and local. Saving shows at once and goes through the server,
        which declines a count below zero: the saved count then goes back.
      </p>
    </header>
    <p class="font-mono text-4xl">{{ count }}</p>
    <div class="flex gap-2">
      <Button variant="outline" @click="count--">−</Button>
      <Button variant="outline" @click="count++">+</Button>
      <Button @click="save(count)">Save</Button>
    </div>
    <p class="text-sm text-zinc-500">Saved on the server: {{ saved }}</p>
  </div>
</template>
