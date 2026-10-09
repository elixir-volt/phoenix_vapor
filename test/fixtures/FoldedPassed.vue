<script setup lang="ts">
import { ref } from "vue"
import PassedTabs from "./components/PassedTabs.vue"

const choice = ref<"a" | "b">("a")
</script>

<template>
  <PassedTabs v-model="choice" />
</template>
