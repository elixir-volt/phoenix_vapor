<script setup lang="ts">
import { ref, computed } from "vue"
import {
  TooltipProvider, TabsRoot, TabsList, TabsTrigger, TabsContent,
  DialogRoot, DialogTrigger, DialogPortal, DialogContent,
  TooltipRoot, TooltipTrigger,
} from "reka-ui"

defineProps<{ name: string; tags: string[] }>()

const tab = ref<"greeting" | "other">("greeting")
const target = ref<string | null>(null)
const confirming = computed(() => target.value !== null)
</script>

<template>
  <TooltipProvider>
    <TabsRoot v-model="tab">
      <TabsList>
        <TabsTrigger value="greeting">Greeting</TabsTrigger>
        <TabsTrigger value="other">Other</TabsTrigger>
      </TabsList>
      <TabsContent value="greeting"><p>Hello {{ name }}</p></TabsContent>
      <TabsContent value="other"><p>Other</p></TabsContent>
    </TabsRoot>
    <ul>
      <li v-for="tag in tags" :key="tag">
        <TooltipRoot><TooltipTrigger>{{ tag }}</TooltipTrigger></TooltipRoot>
      </li>
    </ul>
    <DialogRoot :open="confirming" @update:open="open => { if (!open) target = null }">
      <DialogTrigger>Remove</DialogTrigger>
      <DialogPortal><DialogContent>Remove {{ name }}?</DialogContent></DialogPortal>
    </DialogRoot>
  </TooltipProvider>
</template>
