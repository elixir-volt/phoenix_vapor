<script setup lang="ts">
import { ref } from "vue"
import { TabsRoot, TabsList, TabsTrigger } from "reka-ui"

const left = ref<"a" | "b">("a")
const right = ref<"a" | "b">("b")
</script>

<template>
  <TabsRoot v-model="left">
    <TabsList><TabsTrigger value="a">A</TabsTrigger><TabsTrigger value="b">B</TabsTrigger></TabsList>
  </TabsRoot>
  <TabsRoot v-model="right">
    <TabsList><TabsTrigger value="a">A</TabsTrigger><TabsTrigger value="b">B</TabsTrigger></TabsList>
  </TabsRoot>
</template>
