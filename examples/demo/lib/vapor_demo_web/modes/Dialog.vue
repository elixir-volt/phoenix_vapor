<script setup>
import { ref } from "vue"
import { DialogRoot, DialogTrigger, DialogPortal, DialogOverlay, DialogContent, DialogTitle, DialogDescription, DialogClose } from "reka-ui"

const open = ref(false)

function toggle() {
  open.value = !open.value
}
</script>

<template>
  <div class="space-y-6">
    <header>
      <h1 class="text-2xl font-bold tracking-tight text-zinc-900">Full runtime</h1>
      <p class="text-sm text-zinc-500">
        Vue itself renders this component on the server, in QuickBEAM, with Reka UI bundled for it:
        its ARIA attributes, provide/inject and state are all computed on the BEAM. No Vue runs in the browser.
      </p>
    </header>

    <DialogRoot :open="open" @update:open="v => open = v">
      <DialogTrigger as-child>
        <button class="px-4 py-2 rounded-md bg-zinc-900 text-white hover:bg-zinc-800" phx-click="toggle">
          Open Dialog
        </button>
      </DialogTrigger>
      <DialogPortal>
        <DialogOverlay class="fixed inset-0 bg-black/50" />
        <DialogContent class="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-white rounded-lg p-6 shadow-xl max-w-md w-full">
          <DialogTitle class="text-lg font-semibold">Edit Profile</DialogTitle>
          <DialogDescription class="text-sm text-zinc-500 mt-1">
            Make changes to your profile here.
          </DialogDescription>
          <div class="mt-4 space-y-3">
            <input type="text" placeholder="Name" class="w-full px-3 py-2 border border-zinc-300 rounded-md" />
            <input type="email" placeholder="Email" class="w-full px-3 py-2 border border-zinc-300 rounded-md" />
          </div>
          <div class="mt-4 flex justify-end gap-2">
            <DialogClose as-child>
              <button class="px-4 py-2 rounded-md border border-zinc-300 hover:bg-zinc-100" phx-click="toggle">Cancel</button>
            </DialogClose>
            <DialogClose as-child>
              <button class="px-4 py-2 rounded-md bg-zinc-900 text-white hover:bg-zinc-800" phx-click="toggle">Save Changes</button>
            </DialogClose>
          </div>
        </DialogContent>
      </DialogPortal>
    </DialogRoot>

    <p class="text-xs text-zinc-400">Dialog state: {{ open ? "open" : "closed" }}</p>
  </div>
</template>
