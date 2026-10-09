<script setup lang="ts">
import { ref } from "vue"
import ModelSwitch from "./components/ModelSwitch.vue"

const alerts = ref(true)
</script>

<template>
  <label for="alerts">Alerts <ModelSwitch id="alerts" v-model="alerts" /></label>
</template>
