defmodule VaporDemoWeb.Modes.CompareLive do
  @moduledoc "The same template in HEEx and in `~VUE`, which compile to the same rendered structs."

  use VaporDemoWeb, :live_view
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
       page_title: "HEEx vs ~VUE",
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
      <header>
        <h1 class="text-2xl font-bold tracking-tight text-zinc-900">HEEx vs ~VUE</h1>
        <p class="text-sm text-zinc-500">Same features, different syntax, the same %Rendered{} output.</p>
      </header>

      <div class="grid gap-6 md:grid-cols-2">
        <div>
          <h2 class="mb-3 text-xs font-semibold uppercase tracking-wide text-zinc-400">HEEx</h2>
          <pre class="overflow-x-auto whitespace-pre rounded-lg border border-zinc-200 bg-white p-4 text-sm">{{ heex_code }}</pre>
        </div>
        <div>
          <h2 class="mb-3 text-xs font-semibold uppercase tracking-wide text-zinc-400">~VUE</h2>
          <pre class="overflow-x-auto whitespace-pre rounded-lg border border-zinc-200 bg-white p-4 text-sm">{{ vue_code }}</pre>
        </div>
      </div>

      <section class="space-y-4 border-t border-zinc-200 pt-6">
        <h2 class="text-lg font-semibold text-zinc-900">This page is ~VUE</h2>

        <div class="flex items-center gap-4">
          <button phx-click="dec" class="rounded-md border border-zinc-300 px-4 py-2">−</button>
          <span class="w-16 text-center font-mono text-3xl">{{ count }}</span>
          <button phx-click="inc" class="rounded-md bg-zinc-900 px-4 py-2 text-white">+</button>
        </div>

        <div>
          <ul class="list-inside list-disc text-sm">
            <li v-for="item in items">{{ item }}</li>
          </ul>
          <div class="mt-2 flex gap-2">
            <button phx-click="add" class="rounded-md border border-zinc-300 px-3 py-1 text-sm">Add item</button>
            <button phx-click="remove" class="rounded-md border border-zinc-300 px-3 py-1 text-sm">Remove last</button>
          </div>
        </div>

        <div>
          <button phx-click="toggle" class="rounded-md border border-zinc-300 px-3 py-1 text-sm">Toggle</button>
          <p v-if="show" class="mt-1 text-sm font-medium text-emerald-700">Visible</p>
          <p v-else class="mt-1 text-sm font-medium text-zinc-500">Hidden</p>
        </div>
      </section>
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
