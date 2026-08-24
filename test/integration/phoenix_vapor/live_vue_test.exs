defmodule PhoenixVapor.Integration.LiveVueTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  defmodule ComposedLive do
    use Phoenix.LiveView

    use PhoenixVapor,
      file: "../../fixtures/Probe.vue",
      runtime: :full,
      bundle: "priv/js/reka-dialog.js"

    def mount(params, session, socket) do
      {:ok, socket} = super(params, session, socket)
      {:ok, Phoenix.Component.assign(socket, :host_mounted, true)}
    end

    def render(assigns), do: super(assigns)

    def handle_event("host-event", _params, socket) do
      {:noreply, Phoenix.Component.assign(socket, :host_event, true)}
    end

    def handle_event(event, params, socket), do: super(event, params, socket)

    def terminate(reason, socket) do
      send(self(), {:host_terminated, reason})
      super(reason, socket)
    end
  end

  test "assigns the bundled component export before mounting" do
    {setup, handlers} =
      PhoenixVapor.LiveVue.compile_sfc("test/fixtures/Probe.vue")

    assert handlers == []
    assert setup =~ "globalThis.__sfc_component = (function()"
    assert setup =~ "Vue.createApp(globalThis.__sfc_component).mount(document.body)"
  end

  test "resolves sibling Vue imports from the source component directory" do
    {setup, handlers} =
      PhoenixVapor.LiveVue.compile_sfc("test/fixtures/Parent.vue")

    assert handlers == []
    assert setup =~ "child component"
    refute setup =~ System.tmp_dir!()
  end

  test "composes generated callbacks with host LiveView callbacks" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: nil}}

    assert {:ok, mounted} = ComposedLive.mount(%{}, %{}, socket)
    assert mounted.assigns.host_mounted
    assert is_pid(mounted.assigns.__vue_runtime__)

    assert %Phoenix.LiveView.Rendered{} = ComposedLive.render(mounted.assigns)

    assert {:noreply, handled} = ComposedLive.handle_event("host-event", %{}, mounted)
    assert handled.assigns.host_event

    assert :ok = ComposedLive.terminate(:shutdown, handled)
    assert_received {:host_terminated, :shutdown}
  end
end
