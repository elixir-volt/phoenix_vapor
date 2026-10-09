<script setup lang="ts">
import { ref } from "vue"
import { TabsRoot, TabsList, TabsTrigger } from "reka-ui"

const query = ref("")
</script>

<template>
  <TabsRoot :model-value="query">
    <TabsList><TabsTrigger value="">All</TabsTrigger><TabsTrigger value="a">A</TabsTrigger></TabsList>
  </TabsRoot>
</template>
