defmodule PhoenixVaporDemoWeb.HomeLive do
  use PhoenixVaporDemoWeb, :live_view
  use PhoenixVapor

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       tiers: [
         %{
           title: "~VUE Sigil",
           path: "/counter",
           desc: "Vue template syntax in any LiveView — {{ }}, v-for, v-if, :class, @click",
           tag: "Drop-in"
         },
         %{
           title: ".vue SFC",
           path: "/reactive",
           desc: "A complete LiveView from a single .vue file — ref(), computed(), functions → mount + render + handle_event",
           tag: "Zero Elixir"
         },
         %{
           title: "Vapor DOM",
           path: "/vapor-test",
           desc: "Bypass morphdom entirely — direct DOM writes from LiveView diffs, ~50μs per patch",
           tag: "Performance"
         }
       ],
       more: [
         %{title: "Todo List", path: "/todo", desc: "v-for, v-if, :class, filtering"},
         %{title: "Feature Showcase", path: "/showcase", desc: "Expressions, ternaries, .length, .toUpperCase()"},
         %{title: "Comparison", path: "/compare", desc: "Same component in HEEx vs ~VUE side by side"}
       ]
     )}
  end

  def render(assigns) do
    ~VUE"""
    <div class="space-y-8">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Phoenix Vapor</h1>
        <p class="text-gray-500 mt-1">Vue templates → native <code class="bg-gray-100 px-1 rounded text-sm">%Rendered{}</code> structs — no JS runtime, no virtual DOM</p>
      </div>

      <div class="grid gap-4">
        <a v-for="tier in tiers" :href="tier.path" class="block p-5 border-2 rounded-lg hover:border-blue-500 hover:shadow-md transition-all">
          <div class="flex items-center gap-2">
            <h2 class="text-xl font-bold">{{ tier.title }}</h2>
            <span class="text-xs font-medium px-2 py-0.5 rounded-full bg-blue-100 text-blue-700">{{ tier.tag }}</span>
          </div>
          <p class="text-gray-500 mt-1">{{ tier.desc }}</p>
        </a>
      </div>

      <div>
        <h3 class="text-sm font-semibold text-gray-400 uppercase tracking-wide mb-3">More examples</h3>
        <div class="grid gap-2">
          <a v-for="item in more" :href="item.path" class="block p-3 border rounded hover:border-gray-400 transition-colors">
            <span class="font-medium">{{ item.title }}</span>
            <span class="text-gray-400 ml-2">{{ item.desc }}</span>
          </a>
        </div>
      </div>

      <div class="text-sm text-gray-400 border-t pt-4">
        <p>Every page in this app uses Vue template syntax rendered server-side via Rust NIFs.</p>
        <p>Same WebSocket. Same diff protocol. Same LiveView client. Just faster.</p>
      </div>
    </div>
    """
  end
end
