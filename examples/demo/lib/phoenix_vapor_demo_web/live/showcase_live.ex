defmodule PhoenixVaporDemoWeb.ShowcaseLive do
  use PhoenixVaporDemoWeb, :live_view
  use PhoenixVapor

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       name: "World",
       show_greeting: true,
       items: ["Elixir", "Vue", "Vapor"],
       theme: "light",
       count: 0,
       temperature: 22
     )}
  end

  def render(assigns) do
    ~VUE"""
    <div class="space-y-8">
      <h2 class="text-2xl font-bold">Feature Showcase</h2>

      <section class="space-y-2">
        <h3 class="text-lg font-semibold">Text Interpolation + Expressions</h3>
        <p>Hello, <strong>{{ name }}</strong>!</p>
        <p>Name length: {{ name.length }}</p>
        <p>Uppercased: {{ name.toUpperCase() }}</p>
        <p>Temperature: {{ temperature }}°C — {{ temperature > 30 ? "Hot! 🔥" : temperature > 20 ? "Nice 😎" : "Cold 🥶" }}</p>
      </section>

      <section class="space-y-2">
        <h3 class="text-lg font-semibold">Dynamic Attributes</h3>
        <div :class="theme === 'dark' ? 'bg-gray-800 text-white p-4 rounded' : 'bg-gray-100 text-gray-800 p-4 rounded'">
          <p>Current theme: <strong>{{ theme }}</strong></p>
          <button phx-click="toggle_theme" class="mt-2 px-3 py-1 border rounded">Toggle theme</button>
        </div>
      </section>

      <section class="space-y-2">
        <h3 class="text-lg font-semibold">v-if / v-else</h3>
        <button phx-click="toggle_greeting" class="px-3 py-1 bg-purple-500 text-white rounded">Toggle greeting</button>
        <p v-if="show_greeting" class="text-green-600 font-bold">👋 Greetings are ON</p>
        <p v-else class="text-red-600 font-bold">🙈 Greetings are OFF</p>
      </section>

      <section class="space-y-2">
        <h3 class="text-lg font-semibold">v-for</h3>
        <ul class="list-disc list-inside">
          <li v-for="item in items">{{ item }}</li>
        </ul>
        <div class="flex gap-2">
          <button phx-click="add_item" class="px-3 py-1 bg-blue-500 text-white rounded">Add item</button>
          <button phx-click="remove_item" class="px-3 py-1 bg-red-500 text-white rounded">Remove last</button>
        </div>
        <p class="text-sm text-gray-500">{{ items.length }} items</p>
      </section>

      <section class="space-y-2">
        <h3 class="text-lg font-semibold">Counter with Expressions</h3>
        <p class="text-3xl font-mono">{{ count }}</p>
        <p>{{ count === 0 ? "Zero" : count > 0 ? "Positive" : "Negative" }}</p>
        <div class="flex gap-2">
          <button phx-click="dec" class="px-4 py-2 bg-red-500 text-white rounded">−</button>
          <button phx-click="inc" class="px-4 py-2 bg-green-500 text-white rounded">+</button>
        </div>
      </section>
    </div>
    """
  end

  def handle_event("toggle_theme", _, socket) do
    theme = if socket.assigns.theme == "light", do: "dark", else: "light"
    {:noreply, assign(socket, theme: theme)}
  end

  def handle_event("toggle_greeting", _, socket) do
    {:noreply, update(socket, :show_greeting, &(!&1))}
  end

  def handle_event("add_item", _, socket) do
    n = length(socket.assigns.items) + 1
    {:noreply, update(socket, :items, &(&1 ++ ["Item #{n}"]))}
  end

  def handle_event("remove_item", _, socket) do
    {:noreply, update(socket, :items, fn items -> Enum.slice(items, 0..-2//1) end)}
  end

  def handle_event("inc", _, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
  def handle_event("dec", _, socket), do: {:noreply, update(socket, :count, &(&1 - 1))}
end
