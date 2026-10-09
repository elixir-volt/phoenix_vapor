<script setup lang="ts">
// Three bars filled by priority, or an alert square for urgent.
defineProps<{ priority: string }>()
</script>

<template>
  <svg class="size-3.5 shrink-0" viewBox="0 0 14 14" :aria-label="priority + ' priority'" role="img">
    <g v-if="priority === 'urgent'">
      <rect x="1" y="1" width="12" height="12" rx="3" fill="#f2555a" />
      <path d="M7 3.8v3.9" stroke="#fff" stroke-width="1.6" stroke-linecap="round" />
      <circle cx="7" cy="10" r="0.95" fill="#fff" />
    </g>
    <g v-else-if="priority === 'none'" fill="#6b6b74">
      <rect x="1.5" y="6.3" width="2.4" height="1.4" rx="0.7" />
      <rect x="5.8" y="6.3" width="2.4" height="1.4" rx="0.7" />
      <rect x="10.1" y="6.3" width="2.4" height="1.4" rx="0.7" />
    </g>
    <g v-else>
      <rect x="1.5" y="8" width="2.6" height="4.5" rx="0.8" fill="currentColor" class="text-fg-2" />
      <rect x="5.7" y="5" width="2.6" height="7.5" rx="0.8" :fill="priority === 'low' ? '#3a3a42' : 'currentColor'" class="text-fg-2" />
      <rect x="9.9" y="2" width="2.6" height="10.5" rx="0.8" :fill="priority === 'high' ? 'currentColor' : '#3a3a42'" class="text-fg-2" />
    </g>
  </svg>
</template>
