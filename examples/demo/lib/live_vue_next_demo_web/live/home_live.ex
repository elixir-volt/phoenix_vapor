defmodule LiveVueNextDemoWeb.HomeLive do
  use LiveVueNextDemoWeb, :live_view
  use LiveVueNext

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       demos: [
         %{path: "/counter", title: "Counter", desc: "Simple counter with phx-click events"},
         %{path: "/todo", title: "Todo List", desc: "v-for, conditional rendering, dynamic attrs"},
         %{path: "/showcase", title: "Feature Showcase", desc: "All features in one page"},
         %{path: "/reactive", title: "Reactive Counter", desc: ".vue SFC with <script setup> — zero Elixir code"}
       ]
     )}
  end

  def render(assigns) do
    ~VUE"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold">LiveVueNext Demo</h1>
        <p class="text-gray-500 mt-1">Vue templates compiled to native LiveView rendered structs via Vapor IR</p>
      </div>

      <div class="grid gap-4">
        <a v-for="demo in demos" :href="demo.path" class="block p-4 border rounded-lg hover:border-blue-500 hover:shadow transition-all">
          <h2 class="text-xl font-semibold">{{ demo.title }}</h2>
          <p class="text-gray-500 mt-1">{{ demo.desc }}</p>
        </a>
      </div>

      <div class="text-sm text-gray-400 border-t pt-4 space-y-1">
        <p>This entire app uses Vue template syntax rendered server-side.</p>
        <p>No JavaScript runtime. No virtual DOM. No wrapper divs.</p>
        <p>Every page above is a Phoenix LiveView using <code class="bg-gray-100 px-1 rounded">~VUE</code> sigil.</p>
      </div>
    </div>
    """
  end
end
