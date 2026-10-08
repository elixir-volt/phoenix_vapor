<script setup>
import { computed } from "vue"
import { useClipboard } from "@vueuse/core"

const props = defineProps(["count"])

// Read only by the template: no Elixir code names it.
const { copied: clipboardWasCopied } = useClipboard()

// Evaluated on every render, beside the recorded state.
const doubled = computed(() => props.count * 2)
</script>

<template><p v-if="clipboardWasCopied">Copied {{ doubled }}</p></template>
