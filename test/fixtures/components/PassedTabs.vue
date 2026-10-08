<script setup lang="ts">
import { TabsRoot, TabsList, TabsTrigger } from "reka-ui"

// A string here; the parent's type says which strings.
const model = defineModel<string>()
</script>

<template>
  <TabsRoot v-model="model">
    <TabsList><TabsTrigger value="a">A</TabsTrigger><TabsTrigger value="b">B</TabsTrigger></TabsList>
  </TabsRoot>
</template>
