<script setup>
import { ref, computed } from "vue"

const count = ref(0)
const doubled = computed(() => count * 2)

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
  <div>
    <p>{{ count }}</p>
    <p>{{ doubled }}</p>
    <button @click="increment">+</button>
    <button @click="decrement">-</button>
    <button @click="reset">Reset</button>
  </div>
</template>
