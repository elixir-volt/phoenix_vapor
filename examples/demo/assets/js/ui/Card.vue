<script setup lang="ts">
import { card } from "./variants" with { type: "macro" }

defineProps<{ title: string; description?: string }>()
const styles = card()
</script>

<template>
  <section :class="styles.root()">
    <header :class="styles.header()">
      <h3 :class="styles.title()">{{ title }}</h3>
      <p v-if="description" :class="styles.description()">{{ description }}</p>
    </header>
    <div :class="styles.body()"><slot /></div>
  </section>
</template>
