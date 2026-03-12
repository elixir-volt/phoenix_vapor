defmodule PhoenixVaporDemoWeb.VaporTestLive do
  use PhoenixVaporDemoWeb, :live_view
  use PhoenixVapor

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0, label: "hello")}
  end

  @impl true
  def render(assigns) do
    split =
      Vize.vapor_split!(~s[<div><p :class="label">Count: {{ count }}</p><button @click="increment">+</button></div>])

    PhoenixVapor.Renderer.to_rendered(split, assigns, vapor_metadata: true)
  end

  @impl true
  def handle_event("increment", _, socket) do
    {:noreply, assign(socket, count: socket.assigns.count + 1)}
  end
end
