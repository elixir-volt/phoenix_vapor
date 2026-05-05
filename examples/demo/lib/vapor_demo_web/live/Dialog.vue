<script setup>
import { ref } from "vue"
import { DialogRoot, DialogTrigger, DialogPortal, DialogOverlay, DialogContent, DialogTitle, DialogDescription, DialogClose } from "reka-ui"

const open = ref(false)

function toggle() {
  open.value = !open.value
}
</script>

<template>
  <div class="space-y-4">
    <h2 class="text-2xl font-bold">Reka UI Dialog</h2>
    <p class="text-sm text-gray-500">
      Server-side rendered Vue component library via QuickBEAM.
      Full ARIA attributes, reactive state, provide/inject — all running on the BEAM.
    </p>

    <DialogRoot :open="open" @update:open="v => open = v">
      <DialogTrigger as-child>
        <button class="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700" phx-click="toggle">
          Open Dialog
        </button>
      </DialogTrigger>
      <DialogPortal>
        <DialogOverlay class="fixed inset-0 bg-black/50" />
        <DialogContent class="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-white rounded-lg p-6 shadow-xl max-w-md w-full">
          <DialogTitle class="text-lg font-semibold">Edit Profile</DialogTitle>
          <DialogDescription class="text-sm text-gray-500 mt-1">
            Make changes to your profile here.
          </DialogDescription>
          <div class="mt-4 space-y-3">
            <input type="text" placeholder="Name" class="w-full px-3 py-2 border rounded" />
            <input type="email" placeholder="Email" class="w-full px-3 py-2 border rounded" />
          </div>
          <div class="mt-4 flex justify-end gap-2">
            <DialogClose as-child>
              <button class="px-4 py-2 bg-gray-200 rounded hover:bg-gray-300" phx-click="toggle">Cancel</button>
            </DialogClose>
            <DialogClose as-child>
              <button class="px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700" phx-click="toggle">Save Changes</button>
            </DialogClose>
          </div>
        </DialogContent>
      </DialogPortal>
    </DialogRoot>

    <p class="text-xs text-gray-400 mt-4">
      Dialog state: {{ open ? "open" : "closed" }}
      · ARIA attributes rendered server-side
    </p>
  </div>
</template>
