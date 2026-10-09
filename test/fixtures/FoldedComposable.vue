<script setup lang="ts">
import { useLocalStorage } from "@vueuse/core"
import { TabsRoot, TabsList, TabsTrigger } from "reka-ui"

// Composable state: only the browser has it, until a replay records it.
const tab = useLocalStorage<"a" | "b">("tab", "a")
</script>

<template>
  <TabsRoot v-model="tab">
    <TabsList><TabsTrigger value="a">A</TabsTrigger><TabsTrigger value="b">B</TabsTrigger></TabsList>
  </TabsRoot>
</template>
