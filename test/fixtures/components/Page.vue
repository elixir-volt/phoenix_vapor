<script setup lang="ts">
import Card from "./Card.vue"
import Button from "./Button.vue"

defineProps<{ name: string; busy: boolean }>()
</script>

<template>
  <main>
    <Card :title="name">
      <template #default>
        <Button variant="ghost" size="sm" class="w-full" type="submit" :disabled="busy" @click="save">Save {{ name }}</Button>
        <Button />
      </template>
      <template #footer="{ count, label }">{{ count }} {{ label }}</template>
    </Card>
  </main>
</template>
