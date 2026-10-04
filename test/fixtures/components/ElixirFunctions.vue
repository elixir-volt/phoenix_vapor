<script setup lang="ts">
defineProps<{ members: { name: string; role: string }[] }>()

function roleLabel(role: string) {
  return role === "owner" ? "Owner" : "Member"
}
</script>

<script lang="elixir">
def role_label("owner"), do: "Owner"
def role_label(_role), do: "Member"
</script>

<template>
  <ul>
    <li v-for="member in members" :key="member.name">{{ member.name }}: {{ roleLabel(member.role) }}</li>
  </ul>
</template>
