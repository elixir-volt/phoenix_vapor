<script setup lang="ts">
import { ref } from "vue"
import { TabsRoot, TabsList, TabsTrigger, TabsContent } from "reka-ui"

defineProps<{ name: string }>()

// Read only by the folded tabs.
const tab = ref<"general" | "members" | "notifications">("general")
</script>

<template>
  <TabsRoot v-model="tab">
    <TabsList>
      <TabsTrigger value="general">General</TabsTrigger>
      <TabsTrigger value="members">Members</TabsTrigger>
      <TabsTrigger value="notifications">Notifications</TabsTrigger>
    </TabsList>
    <TabsContent value="general"><p>Hello {{ name }}</p></TabsContent>
    <TabsContent value="members"><p>Members of {{ name }}</p></TabsContent>
    <TabsContent value="notifications"><p>Notifications</p></TabsContent>
  </TabsRoot>
</template>
