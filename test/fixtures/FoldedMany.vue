<script setup lang="ts">
import { ref } from "vue"
import { ConfigProvider, SwitchRoot } from "reka-ui"

// Seven switches folded together: 128 combinations, over the 64 a fold takes.
const a = ref(false)
const b = ref(false)
const c = ref(false)
const d = ref(false)
const e = ref(false)
const f = ref(false)
const g = ref(false)
</script>

<template>
  <ConfigProvider>
    <SwitchRoot v-model="a" /><SwitchRoot v-model="b" /><SwitchRoot v-model="c" />
    <SwitchRoot v-model="d" /><SwitchRoot v-model="e" /><SwitchRoot v-model="f" />
    <SwitchRoot v-model="g" />
  </ConfigProvider>
</template>
