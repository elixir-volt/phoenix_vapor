defmodule PhoenixVaporDemoWeb.CompareLive do
  use PhoenixVaporDemoWeb, :live_view
  use PhoenixVapor

  @heex_code """
  <p><%= @count %></p>

  <%= for item <- @items do %>
    <li><%= item %></li>
  <% end %>

  <%= if @show do %>
    <p>Visible</p>
  <% else %>
    <p>Hidden</p>
  <% end %>

  <button phx-click="inc">+</button>\
  """

  @vue_code """
  <p>{{ count }}</p>

  <li v-for="item in items">
    {{ item }}
  </li>

  <p v-if="show">Visible</p>
  <p v-else>Hidden</p>

  <button @click="inc">+</button>\
  """

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       count: 0,
       items: ["Elixir", "Vue", "Vapor"],
       show: true,
       heex_code: @heex_code,
       vue_code: @vue_code
     )}
  end

  def render(assigns) do
    ~VUE"""
    <div class="space-y-8">
      <div>
        <h2 class="text-2xl font-bold">HEEx vs ~VUE</h2>
        <p class="text-gray-500">Same features, different syntax. Same %Rendered{} output.</p>
      </div>

      <div class="grid grid-cols-2 gap-6">
        <div>
          <h3 class="text-sm font-semibold text-gray-400 uppercase tracking-wide mb-3">HEEx</h3>
          <pre class="text-sm bg-gray-50 p-4 rounded-lg overflow-x-auto border whitespace-pre">{{ heex_code }}</pre>
        </div>

        <div>
          <h3 class="text-sm font-semibold text-gray-400 uppercase tracking-wide mb-3">~VUE</h3>
          <pre class="text-sm bg-gray-50 p-4 rounded-lg overflow-x-auto border whitespace-pre">{{ vue_code }}</pre>
        </div>
      </div>

      <div class="border-t pt-6 space-y-4">
        <h3 class="text-lg font-semibold">Live demo (this is ~VUE)</h3>

        <div class="flex items-center gap-4">
          <button phx-click="dec" class="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600">−</button>
          <span class="text-3xl font-mono w-16 text-center">{{ count }}</span>
          <button phx-click="inc" class="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600">+</button>
        </div>

        <div>
          <ul class="list-disc list-inside">
            <li v-for="item in items">{{ item }}</li>
          </ul>
          <div class="flex gap-2 mt-2">
            <button phx-click="add" class="px-3 py-1 bg-blue-500 text-white rounded text-sm">Add item</button>
            <button phx-click="remove" class="px-3 py-1 bg-gray-400 text-white rounded text-sm">Remove last</button>
          </div>
        </div>

        <div>
          <button phx-click="toggle" class="px-3 py-1 bg-purple-500 text-white rounded text-sm">Toggle</button>
          <p v-if="show" class="mt-1 text-green-600 font-medium">✓ Visible</p>
          <p v-else class="mt-1 text-red-600 font-medium">✗ Hidden</p>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("inc", _, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
  def handle_event("dec", _, socket), do: {:noreply, update(socket, :count, &(&1 - 1))}
  def handle_event("toggle", _, socket), do: {:noreply, update(socket, :show, &(!&1))}

  def handle_event("add", _, socket) do
    n = length(socket.assigns.items) + 1
    {:noreply, update(socket, :items, &(&1 ++ ["Item #{n}"]))}
  end

  def handle_event("remove", _, socket) do
    {:noreply, update(socket, :items, fn items -> Enum.slice(items, 0..-2//1) end)}
  end
end
