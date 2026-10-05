<script setup lang="ts">
import Badge from "@/ui/Badge.vue"

type Member = { id: number; name: string; email: string; role: string; active: boolean }

defineProps<{ project: { name: string }; members: Member[] }>()

function roleTone(role: string) {
  return role === "owner" ? "warning" : role === "admin" ? "success" : "neutral"
}
</script>

<script lang="elixir">
def role_tone("owner"), do: "warning"
def role_tone("admin"), do: "success"
def role_tone(_role), do: "neutral"
</script>

<template>
  <div class="space-y-6">
    <header>
      <h1 class="text-2xl font-bold tracking-tight text-zinc-900">Server-only .vue</h1>
      <p class="text-sm text-zinc-500">
        A .vue file with props and no client state renders on the server alone. Remove a member in
        Settings and this page updates over LiveView.
      </p>
    </header>
    <h2 class="text-lg font-semibold">{{ project.name }} team</h2>
    <ul class="divide-y divide-zinc-100 rounded-lg border border-zinc-200 bg-white">
      <li v-for="member in members" :key="member.id" class="flex items-center justify-between px-4 py-2">
        <div>
          <p class="text-sm font-medium" :class="{ 'text-zinc-400': !member.active }">{{ member.name }}</p>
          <p class="text-xs text-zinc-500">{{ member.email }}</p>
        </div>
        <Badge :tone="roleTone(member.role)">{{ member.role }}</Badge>
      </li>
    </ul>
  </div>
</template>
