<script setup lang="ts">
import { card } from "./variants" with { type: "macro" }

defineProps<{ title: string }>()
const styles = card()
</script>

<template>
  <section :class="styles.root()">
    <h3 :class="styles.title()">{{ title }}</h3>
    <slot />
    <footer><slot name="footer" :count="3" label="items" /></footer>
  </section>
</template>
