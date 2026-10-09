<script setup lang="ts">
import { ref, computed } from "vue"
import {
  TabsRoot, TabsList, TabsTrigger, TabsContent,
  DialogRoot, DialogTrigger, DialogPortal, DialogOverlay, DialogContent, DialogTitle, DialogDescription, DialogClose,
} from "reka-ui"
import Button from "@/ui/Button.vue"
import Badge from "@/ui/Badge.vue"
import Card from "@/ui/Card.vue"
import Switch from "@/ui/Switch.vue"
import Select from "@/ui/Select.vue"

type Member = { id: number; name: string; email: string; role: string; active: boolean }

// The server owns both; the browser changes them through server actions.
const project = defineModel<{ name: string; plan: string }>("project", { required: true })
const members = defineModel<Member[]>("members", { required: true })

// Typed as their values, so the server folds the tabs and the filter once
// for each, and a session replay shows the recorded one.
const tab = ref<"general" | "members" | "notifications">("general")
const name = ref(project.value.name)
const emailAlerts = ref(true)
const weeklyDigest = ref(false)
const roleFilter = ref<"all" | "owner" | "admin" | "member">("all")
const removeTarget = ref<Member | null>(null)

const roles = [
  { value: "all", label: "All roles" },
  { value: "owner", label: "Owner" },
  { value: "admin", label: "Admin" },
  { value: "member", label: "Member" },
]

const roleLabels: Record<string, string> = Object.fromEntries(roles.map(r => [r.value, r.label]))

const visibleMembers = computed(() =>
  roleFilter.value === "all" ? members.value : members.value.filter(m => m.role === roleFilter.value),
)

const dirty = computed(() => name.value !== project.value.name)

function roleTone(role: string) {
  return role === "owner" ? "warning" : role === "admin" ? "success" : "neutral"
}

function saveName(newName: string) {
  "use server"
  project.value = { ...project.value, name: newName }
}

function removeMember(id: number) {
  "use server"
  members.value = members.value.filter(m => m.id !== id)
}

function confirmRemove() {
  if (removeTarget.value) {
    removeMember(removeTarget.value.id)
    removeTarget.value = null
  }
}
</script>

<script lang="elixir">
# roleTone for the server, which renders the first paint without JavaScript.
def role_tone("owner"), do: "warning"
def role_tone("admin"), do: "success"
def role_tone(_role), do: "neutral"
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-6">
    <div class="flex items-center justify-between">
      <div>
        <h2 class="text-2xl font-bold text-zinc-900">{{ project.name }}</h2>
        <p class="text-sm text-zinc-500">Project settings</p>
      </div>
      <Badge :tone="project.plan === 'pro' ? 'success' : 'neutral'">{{ project.plan }}</Badge>
    </div>

    <TabsRoot v-model="tab" class="space-y-4">
      <TabsList class="inline-flex gap-1 rounded-lg bg-zinc-100 p-1">
        <TabsTrigger value="general" class="rounded-md px-3 py-1.5 text-sm data-[state=active]:bg-white data-[state=active]:shadow">General</TabsTrigger>
        <TabsTrigger value="members" class="rounded-md px-3 py-1.5 text-sm data-[state=active]:bg-white data-[state=active]:shadow">Members</TabsTrigger>
        <TabsTrigger value="notifications" class="rounded-md px-3 py-1.5 text-sm data-[state=active]:bg-white data-[state=active]:shadow">Notifications</TabsTrigger>
      </TabsList>

      <TabsContent value="general">
        <Card title="Project name" description="Shown in the sidebar and in invitations.">
          <form class="flex gap-2" @submit.prevent="saveName(name)">
            <input v-model="name" name="name" aria-label="Project name" class="h-9 flex-1 rounded-md border border-zinc-300 px-3 text-sm" />
            <Button type="submit" :disabled="!dirty">Save</Button>
          </form>
        </Card>
      </TabsContent>

      <TabsContent value="members">
        <Card title="Members" :description="`${visibleMembers.length} of ${members.length} members`">
          <div class="mb-3 flex justify-end">
            <Select v-model="roleFilter" :options="roles" :label="roleLabels[roleFilter]" placeholder="Filter by role" />
          </div>
          <ul class="divide-y divide-zinc-100">
            <li v-for="member in visibleMembers" :key="member.id" class="flex items-center justify-between py-2">
              <div>
                <p class="text-sm font-medium" :class="{ 'text-zinc-400': !member.active }">{{ member.name }}</p>
                <p class="text-xs text-zinc-500">{{ member.email }}</p>
              </div>
              <div class="flex items-center gap-2">
                <Badge :tone="roleTone(member.role)">{{ member.role }}</Badge>
                <Button variant="ghost" size="sm" :disabled="member.role === 'owner'" @click="removeTarget = member">Remove</Button>
              </div>
            </li>
          </ul>
        </Card>
      </TabsContent>

      <TabsContent value="notifications">
        <Card title="Notifications">
          <div class="space-y-3">
            <label class="flex items-center justify-between text-sm" for="email-alerts">
              Email alerts <Switch id="email-alerts" v-model="emailAlerts" />
            </label>
            <label class="flex items-center justify-between text-sm" for="weekly-digest">
              Weekly digest <Switch id="weekly-digest" v-model="weeklyDigest" />
            </label>
          </div>
        </Card>
      </TabsContent>
    </TabsRoot>

    <DialogRoot :open="removeTarget !== null" @update:open="open => { if (!open) removeTarget = null }">
      <DialogPortal>
        <DialogOverlay class="fixed inset-0 bg-black/40" />
        <DialogContent class="fixed left-1/2 top-1/2 w-full max-w-sm -translate-x-1/2 -translate-y-1/2 rounded-lg bg-white p-6 shadow-xl">
          <DialogTitle class="text-lg font-semibold">Remove member</DialogTitle>
          <DialogDescription class="mt-1 text-sm text-zinc-500">
            {{ removeTarget?.name }} will lose access to {{ project.name }}.
          </DialogDescription>
          <div class="mt-5 flex justify-end gap-2">
            <DialogClose as-child><Button variant="outline">Cancel</Button></DialogClose>
            <Button variant="destructive" @click="confirmRemove">Remove</Button>
          </div>
        </DialogContent>
      </DialogPortal>
    </DialogRoot>
  </div>
</template>
