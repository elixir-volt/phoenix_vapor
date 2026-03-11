<template>
  <div :class="variant">
    <h2>{{ title }}</h2>
    <p>{{ description }}</p>
  </div>
</template>

<script setup>
defineProps({
  title: String,
  description: String,
  variant: { type: String, default: 'default' }
})
</script>
