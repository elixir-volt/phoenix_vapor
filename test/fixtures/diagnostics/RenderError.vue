<script lang="elixir">
def mount(_params, _session, socket), do: {:ok, socket}
</script>

<template>
  <section>
    <p>{{ title }}</p>
    <p>{{ missing() }}</p>
  </section>
</template>
