<script setup lang="ts">
import { TooltipProvider, TabsRoot, TabsList, TabsTrigger, TabsContent } from "reka-ui"

defineProps<{ name: string }>()
</script>

<template>
  <TooltipProvider>
    <TabsRoot default-value="greeting">
      <TabsList>
        <TabsTrigger value="greeting">Greeting</TabsTrigger>
      </TabsList>
      <TabsContent value="greeting"><p>Hello {{ name }}</p></TabsContent>
    </TabsRoot>
  </TooltipProvider>
</template>
