defmodule VaporDemoWeb.Modes.SigilLive do
  @moduledoc "A LiveView whose template is Vue syntax in the `~VUE` sigil."

  use VaporDemoWeb, :live_view
  use PhoenixVapor

  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "~VUE sigil", count: 0)}

  def render(assigns) do
    ~VUE"""
    <div class="space-y-6">
      <header>
        <h1 class="text-2xl font-bold tracking-tight text-zinc-900">~VUE sigil</h1>
        <p class="text-sm text-zinc-500">
          Vue syntax in place of HEEx. The template compiles to LiveView's own rendered structs;
          state and events stay ordinary LiveView.
        </p>
      </header>
      <p class="font-mono text-4xl">{{ count }}</p>
      <div class="flex gap-2">
        <button phx-click="dec" class="rounded-md border border-zinc-300 px-4 py-2">−</button>
        <button phx-click="reset" class="rounded-md border border-zinc-300 px-4 py-2">Reset</button>
        <button phx-click="inc" class="rounded-md bg-zinc-900 px-4 py-2 text-white">+</button>
      </div>
      <p v-if="count < 0" class="text-sm text-amber-700">Below zero</p>
    </div>
    """
  end

  def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
  def handle_event("dec", _params, socket), do: {:noreply, update(socket, :count, &(&1 - 1))}
  def handle_event("reset", _params, socket), do: {:noreply, assign(socket, count: 0)}
end
