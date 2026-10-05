<script setup lang="ts">
import { ref, computed } from "vue"

type Contact = { id: number; name: string }

const props = defineProps<{ title: string }>()
const contacts = defineModel<Contact[]>("contacts", { required: true })

const search = ref("")
const matching = computed(() => contacts.value.filter((c) => c.name.includes(search.value)))

function deleteContact(id: number) {
  "use server"
  contacts.value = contacts.value.filter((c) => c.id !== id)
}
</script>

<template>
  <div>
    <h1>{{ props.title }}</h1>
    <input v-model="search" />
    <p>{{ matching.length }} of {{ contacts.length }}</p>
    <ul>
      <li v-for="contact in matching" :key="contact.id">
        {{ contact.name }} <button @click="deleteContact(contact.id)">Delete</button>
      </li>
    </ul>
  </div>
</template>
