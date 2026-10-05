<script setup>
import { ref } from "vue"

defineProps(["users"])
const search = ref("")

// A parameter named like a prop is the function's own to write.
function clear(users) {
  users = []
  return users
}

function remove(id) {
  "use server"
  users = users.filter((u) => u.id !== id)
}
</script>

<template><p>{{ users.length }} {{ search }} {{ clear }}</p></template>
