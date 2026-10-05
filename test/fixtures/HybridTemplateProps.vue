<script setup>
import { ref } from "vue"

const props = defineProps(["saved", "owner"])

const count = ref(0)

function save(count) {
  "use server"
  props.saved = props.owner ? count : props.saved
}
</script>

<template>
  <div>
    <button @click="count++">{{ count }}</button>
    <p>Saved: {{ props.saved }}</p>
  </div>
</template>
