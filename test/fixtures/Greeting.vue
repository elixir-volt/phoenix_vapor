<script setup>
import { ref } from "vue"

const count = ref(0)
</script>

<template>
  <p>{{ name }} {{ count }}</p>
</template>
