<script setup lang="ts">
import { ref } from "vue"
import { DialogRoot, DialogContent, DialogTitle } from "reka-ui"

type Contact = { id: number; name: string }

defineProps<{ contacts: Contact[] }>()

const target = ref<Contact | null>(null)
</script>

<template>
  <ul>
    <li v-for="contact in contacts" :key="contact.id">
      {{ contact.name }} <button @click="target = contact">Remove</button>
    </li>
  </ul>
  <DialogRoot :open="target !== null" @update:open="open => { if (!open) target = null }">
    <DialogContent><DialogTitle>Remove {{ target ? target.name : "" }}?</DialogTitle></DialogContent>
  </DialogRoot>
</template>
