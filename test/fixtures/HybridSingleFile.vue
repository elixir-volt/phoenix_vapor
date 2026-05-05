<script lang="elixir">
def mount(_params, _session, socket) do
  {:ok, assign(socket, items: ["apple", "banana", "cherry"], title: "Fruits")}
end

def handle_event("deleteItem", %{"name" => name}, socket) do
  items = Enum.reject(socket.assigns.items, &(&1 == name))
  {:noreply, assign(socket, items: items)}
end
</script>

<script setup>
import { ref, computed } from "vue"

const props = defineProps(["items", "title"])

const search = ref("")

const filtered = computed(() =>
  (props.items || []).filter(i => i.toLowerCase().includes(search.value.toLowerCase()))
)

function deleteItem(name) {
  "use server"
  props.items = props.items.filter(i => i !== name)
}
</script>

<template>
  <div>
    <h1>{{ title }}</h1>
    <input :value="search" @input="search = $event.target.value" placeholder="Filter..." />
    <p>{{ filtered.length }} items</p>
    <ul>
      <li v-for="item in filtered" :key="item">
        {{ item }}
        <button @click="deleteItem(item)">×</button>
      </li>
    </ul>
  </div>
</template>
