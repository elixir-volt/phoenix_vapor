<script setup lang="ts">
// A status's icon: a dashed ring for the backlog, a ring for todo, a ring
// filling as the issue moves on, a full disc when it's done.
defineProps<{ status: string }>()
</script>

<template>
  <svg class="size-[13px] shrink-0" viewBox="0 0 14 14" fill="none" aria-hidden="true">
    <circle v-if="status === 'backlog'" cx="7" cy="7" r="6" stroke="#6b6b74" stroke-width="1.6" stroke-dasharray="2.2 2" />
    <circle v-else-if="status === 'todo'" cx="7" cy="7" r="6" stroke="#a9a9b2" stroke-width="1.6" />
    <g v-else-if="status === 'in_progress'">
      <circle cx="7" cy="7" r="6" stroke="#f5a524" stroke-width="1.6" />
      <path d="M7 3.5a3.5 3.5 0 0 1 0 7z" fill="#f5a524" />
    </g>
    <g v-else-if="status === 'in_review'">
      <circle cx="7" cy="7" r="6" stroke="#3dd68c" stroke-width="1.6" />
      <path d="M7 3.5a3.5 3.5 0 1 1-3.5 3.5H7z" fill="#3dd68c" />
    </g>
    <g v-else>
      <circle cx="7" cy="7" r="6.5" fill="#6e7bff" />
      <path d="m4.3 7.2 1.8 1.8 3.6-3.8" stroke="#0a0a14" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
    </g>
  </svg>
</template>
