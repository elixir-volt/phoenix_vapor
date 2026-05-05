<script setup>
defineProps(["items"])
</script>

<template>
  <ul>
    <li v-for="item in items">{{ item }}</li>
  </ul>
</template>
