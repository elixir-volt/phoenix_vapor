<script setup lang="ts">
import { ref } from "vue"
import { TooltipProvider, TabsRoot, TabsList, TabsTrigger, TabsContent } from "reka-ui"

defineProps<{ name: string }>()

const tab = ref("greeting")
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
  </TooltipProvider>
</template>
