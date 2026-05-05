<script lang="elixir">
def mount(_params, _session, socket) do
  {:ok, assign(socket, items: ["one", "two", "three"])}
end
</script>

<template>
  <ul>
    <li v-for="item in items">{{ item }}</li>
  </ul>
</template>
