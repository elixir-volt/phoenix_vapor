<script setup>
import { ref } from "vue"

const count = ref(0)
</script>

<script lang="elixir">
def mount(_params, _session, socket), do: {:ok, socket}
</script>

<template>
  <p>{{ count }}</p>
</template>
