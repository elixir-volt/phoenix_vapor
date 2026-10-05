<script setup>
import { ref } from "vue"

const props = defineProps(["items"])
const search = ref("")

function remove(name) {
  "use server"
  props.items = props.items.filter((i) => i !== name)
}
</script>

<template><p>{{ props.items.length }} {{ search }}</p></template>
