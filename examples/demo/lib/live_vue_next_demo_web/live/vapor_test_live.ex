defmodule LiveVueNextDemoWeb.VaporTestLive do
  use LiveVueNextDemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, count: 0, label: "hello")}
  end

  @impl true
  def render(assigns) do
    ir = Vize.vapor_ir!(~s[<div><p :class="label">Count: {{ count }}</p><button @click="increment">+</button></div>])
    LiveVueNext.Renderer.to_rendered(ir, assigns, vapor_metadata: true)
  end

  @impl true
  def handle_event("increment", _, socket) do
    {:noreply, assign(socket, count: socket.assigns.count + 1)}
  end
end
