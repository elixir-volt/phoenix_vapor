<script setup>
import { ref, computed } from "vue"

const items = ref([])

const count = computed(() => items.length)

function addItem() {
  if (__params.value && __params.value.trim()) {
    items.push(__params.value.trim())
  }
}

function removeItem() {
  items.splice(Number(__params.value), 1)
}

function clearAll() {
  items.splice(0, items.length)
}
</script>

<template>
  <div class="space-y-4">
    <h2 class="text-2xl font-bold">Reactive List</h2>
    <p class="text-sm text-gray-500">
      Persistent Vue reactive state in QuickBEAM — array mutations survive across events.
    </p>

    <form phx-submit="addItem" class="flex gap-2">
      <input
        type="text"
        name="value"
        placeholder="Add item..."
        class="px-3 py-2 border rounded flex-1"
      />
      <button type="submit" class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">
        Add
      </button>
    </form>

    <p class="text-lg font-mono">{{ count }} items</p>

    <div v-for="(item, index) in items" class="flex items-center gap-2 py-1 border-b">
      <span class="flex-1">{{ item }}</span>
      <button
        phx-click="removeItem"
        :phx-value-value="index"
        class="px-2 py-1 text-sm bg-red-200 rounded hover:bg-red-300"
      >
        ×
      </button>
    </div>

    <button
      v-if="count > 0"
      @click="clearAll"
      class="px-4 py-2 bg-gray-500 text-white rounded hover:bg-gray-600"
    >
      Clear all
    </button>
  </div>
</template>
