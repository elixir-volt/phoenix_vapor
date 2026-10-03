<script setup>
function shout(text) {
  return text.toUpperCase()
}
</script>

<template>
  <p>{{ shout(title) }}</p>
</template>
