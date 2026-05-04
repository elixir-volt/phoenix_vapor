defmodule PhoenixVapor.HybridTest do
  use ExUnit.Case, async: true

  defmodule TestLive do
    use Phoenix.LiveView
    use PhoenixVapor.Hybrid, file: "../fixtures/Hybrid.vue"
  end

  defp render_to_html(rendered) do
    dynamic = rendered.dynamic.(false)

    rendered.static
    |> Enum.with_index()
    |> Enum.map(fn {s, i} ->
      case Enum.at(dynamic, i) do
        nil -> s
        %Phoenix.LiveView.Rendered{} = r -> s <> render_to_html(r)
        %Phoenix.LiveView.Comprehension{} = c -> s <> render_comprehension(c)
        d -> s <> to_string(d)
      end
    end)
    |> IO.iodata_to_binary()
  end

  defp render_comprehension(c) do
    c.entries
    |> Enum.map(fn {_, _, f} ->
      d = f.(%{}, false)

      c.static
      |> Enum.with_index()
      |> Enum.map(fn {s, i} ->
        case Enum.at(d, i) do
          nil -> s
          v -> s <> to_string(v)
        end
      end)
      |> IO.iodata_to_binary()
    end)
    |> IO.iodata_to_binary()
  end

  describe "macro generates server functions" do
    test "render/1 is defined" do
      assert function_exported?(TestLive, :render, 1)
    end

    test "handle_event/3 is defined for server actions" do
      assert function_exported?(TestLive, :handle_event, 3)
    end

    test "render produces %Rendered{} with data-pv wrapper" do
      assigns = %{
        users: [%{name: "Alice"}, %{name: "Bob"}],
        title: "Users",
        search: ""
      }

      rendered = TestLive.render(assigns)
      assert %Phoenix.LiveView.Rendered{} = rendered

      html = render_to_html(rendered)
      assert html =~ "data-pv"
      assert html =~ "data-pv-props="
    end

    test "props JSON contains client-consumed props" do
      assigns = %{
        users: [%{name: "Alice"}],
        title: "Dashboard",
        search: ""
      }

      rendered = TestLive.render(assigns)
      html = render_to_html(rendered)

      assert html =~ "Alice"
      assert html =~ "data-pv-props="
    end

    test "inner content renders all slots for first paint" do
      assigns = %{
        users: [%{name: "Alice"}, %{name: "Bob"}],
        title: "My Title",
        search: "test"
      }

      rendered = TestLive.render(assigns)
      html = render_to_html(rendered)

      assert html =~ "My Title"
    end

    test "handle_event exists for deleteUser" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}, live_action: nil},
        private: %{assign_new: {%{}, []}}
      }

      assert {:noreply, _socket} = TestLive.handle_event("deleteUser", %{}, socket)
    end
  end

  describe "client JS generation" do
    test "client JS is accessible via module attribute" do
      js = TestLive.__hybrid_client_js__()
      assert is_binary(js)
      assert byte_size(js) > 0
    end

    test "client JS is valid JavaScript" do
      js = TestLive.__hybrid_client_js__()
      assert {:ok, _} = OXC.parse(js, "output.js")
    end

    test "client JS contains bridge exports" do
      js = TestLive.__hybrid_client_js__()
      assert js =~ "__applyProps"
      assert js =~ "__mount"
      assert js =~ "__serverProps"
    end

    test "client JS contains Vue Vapor render" do
      js = TestLive.__hybrid_client_js__()
      assert js =~ "renderEffect"
      assert js =~ "_template("
    end

    test "client JS has deleteUser as server action" do
      js = TestLive.__hybrid_client_js__()
      assert js =~ "pushEvent"
      assert js =~ ~s("deleteUser")
    end

    test "client JS preserves clearSearch as client handler" do
      js = TestLive.__hybrid_client_js__()
      assert js =~ "clearSearch"
      refute js =~ ~s(pushEvent("clearSearch")
    end
  end

  describe "classification is accessible" do
    test "classification contains binding info" do
      c = TestLive.__hybrid_classification__()
      assert c.bindings["users"] == :server_prop
      assert c.bindings["title"] == :server_prop
      assert {:client_ref, _} = c.bindings["search"]
      assert {:mixed_computed, _, _} = c.bindings["filtered"]
    end

    test "classification contains handler info" do
      c = TestLive.__hybrid_classification__()
      assert {:server_action, _} = c.handlers["deleteUser"]
      assert c.handlers["clearSearch"] == :client_handler
    end

    test "client_props computed correctly" do
      c = TestLive.__hybrid_classification__()
      assert "users" in c.client_props
    end
  end
end
