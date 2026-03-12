defmodule PhoenixVaporDemoWeb.CounterLive do
  use PhoenixVaporDemoWeb, :live_view
  use PhoenixVapor

  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0)}
  end

  def render(assigns) do
    ~VUE"""
    <div class="space-y-4">
      <h2 class="text-2xl font-bold">Counter</h2>
      <p class="text-4xl font-mono">{{ count }}</p>
      <div class="flex gap-2">
        <button phx-click="dec" class="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600">-</button>
        <button phx-click="reset" class="px-4 py-2 bg-gray-500 text-white rounded hover:bg-gray-600">Reset</button>
        <button phx-click="inc" class="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600">+</button>
      </div>
    </div>
    """
  end

  def handle_event("inc", _, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
  def handle_event("dec", _, socket), do: {:noreply, update(socket, :count, &(&1 - 1))}
  def handle_event("reset", _, socket), do: {:noreply, assign(socket, count: 0)}
end
