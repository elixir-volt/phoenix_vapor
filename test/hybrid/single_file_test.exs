defmodule PhoenixVapor.Hybrid.SingleFileTest do
  use ExUnit.Case, async: true

  defmodule FruitsLive do
    use Phoenix.LiveView
    use PhoenixVapor.Hybrid, file: "../fixtures/HybridSingleFile.vue"
  end

  describe "elixir block: mount" do
    test "mount/3 is defined from <script lang=elixir>" do
      assert function_exported?(FruitsLive, :mount, 3)
    end

    test "mount assigns items and title" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}, live_action: nil},
        private: %{assign_new: {%{}, []}}
      }

      {:ok, socket} = FruitsLive.mount(%{}, %{}, socket)
      assert socket.assigns.items == ["apple", "banana", "cherry"]
      assert socket.assigns.title == "Fruits"
    end
  end

  describe "elixir block: handle_event" do
    test "handle_event/3 is defined from <script lang=elixir>" do
      assert function_exported?(FruitsLive, :handle_event, 3)
    end

    test "deleteItem removes the item" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          live_action: nil,
          items: ["apple", "banana", "cherry"]
        },
        private: %{assign_new: {%{}, []}}
      }

      {:noreply, socket} = FruitsLive.handle_event("deleteItem", %{"name" => "banana"}, socket)
      assert socket.assigns.items == ["apple", "cherry"]
    end
  end

  describe "render still works" do
    test "render/1 is defined" do
      assert function_exported?(FruitsLive, :render, 1)
    end

    test "renders items from assigns" do
      assigns = %{items: ["x", "y"], title: "Test"}
      rendered = FruitsLive.render(assigns)
      assert %Phoenix.LiveView.Rendered{} = rendered
    end
  end

  describe "client JS still generated" do
    test "client JS is valid" do
      js = FruitsLive.__hybrid_client_js__()
      assert {:ok, _} = OXC.parse(js, "output.js")
    end

    test "client JS has deleteItem pushEvent" do
      js = FruitsLive.__hybrid_client_js__()
      assert js =~ ~s(pushEvent("deleteItem")
    end
  end

  describe "classification" do
    test "items is a server prop" do
      c = FruitsLive.__hybrid_classification__()
      assert c.bindings["items"] == :server_prop
    end

    test "search is a client ref" do
      c = FruitsLive.__hybrid_classification__()
      assert {:client_ref, _} = c.bindings["search"]
    end

    test "deleteItem is a server action" do
      c = FruitsLive.__hybrid_classification__()
      assert {:server_action, _} = c.handlers["deleteItem"]
    end
  end
end
