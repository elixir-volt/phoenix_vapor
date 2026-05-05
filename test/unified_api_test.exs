defmodule PhoenixVapor.UnifiedAPITest do
  use ExUnit.Case, async: true

  # Mode 1: sigil only (no file)
  defmodule SigilLive do
    use Phoenix.LiveView
    use PhoenixVapor

    def render(assigns) do
      ~VUE"""
      <p>{{ msg }}</p>
      """
    end
  end

  # Mode 2: server-only SFC (no script setup, elixir block)
  defmodule ServerOnlyLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: "fixtures/ServerOnly.vue"
  end

  # Mode 3: server-only SFC with defineProps (no ref = no client JS)
  defmodule ServerOnlyPropsLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: "fixtures/ServerOnlyProps.vue"
  end

  # Mode 4: hybrid SFC (has ref() = client JS generated)
  defmodule HybridLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: "fixtures/Hybrid.vue"
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

  describe "use PhoenixVapor (sigil mode)" do
    test "imports ~VUE sigil" do
      html = SigilLive.render(%{msg: "Hello"}) |> render_to_html()
      assert html =~ "Hello"
    end

    test "no file-related functions" do
      refute function_exported?(SigilLive, :__hybrid_client_js__, 0)
      refute function_exported?(SigilLive, :__hybrid_classification__, 0)
    end
  end

  describe "use PhoenixVapor, file: (server-only, no script setup)" do
    test "render/1 is defined" do
      assert function_exported?(ServerOnlyLive, :render, 1)
    end

    test "mount/3 from elixir block is defined" do
      assert function_exported?(ServerOnlyLive, :mount, 3)
    end

    test "renders template" do
      assigns = %{items: ["a", "b"]}
      html = ServerOnlyLive.render(assigns) |> render_to_html()
      assert html =~ "<li>a</li>"
      assert html =~ "<li>b</li>"
    end

    test "no hybrid client JS" do
      refute function_exported?(ServerOnlyLive, :__hybrid_client_js__, 0)
    end

    test "no phx-hook in rendered HTML" do
      html = ServerOnlyLive.render(%{items: []}) |> render_to_html()
      refute html =~ "phx-hook"
    end
  end

  describe "use PhoenixVapor, file: (server-only with defineProps)" do
    test "render/1 is defined" do
      assert function_exported?(ServerOnlyPropsLive, :render, 1)
    end

    test "renders from assigns" do
      html = ServerOnlyPropsLive.render(%{items: ["x", "y"]}) |> render_to_html()
      assert html =~ "<li>x</li>"
      assert html =~ "<li>y</li>"
    end

    test "no hybrid client JS generated" do
      refute function_exported?(ServerOnlyPropsLive, :__hybrid_client_js__, 0)
    end

    test "no phx-hook in HTML" do
      html = ServerOnlyPropsLive.render(%{items: []}) |> render_to_html()
      refute html =~ "phx-hook"
    end
  end

  describe "use PhoenixVapor, file: (hybrid, has ref())" do
    test "render/1 is defined" do
      assert function_exported?(HybridLive, :render, 1)
    end

    test "hybrid client JS is generated" do
      assert function_exported?(HybridLive, :__hybrid_client_js__, 0)
      js = HybridLive.__hybrid_client_js__()
      assert byte_size(js) > 100
    end

    test "classification is available" do
      c = HybridLive.__hybrid_classification__()
      assert is_map(c.bindings)
    end

    test "has phx-hook in rendered HTML" do
      html = HybridLive.render(%{users: [], title: "T"}) |> render_to_html()
      assert html =~ "phx-hook"
    end
  end

  describe "auto-detection logic" do
    test "no ref() → server-only (no client JS)" do
      refute function_exported?(ServerOnlyPropsLive, :__hybrid_client_js__, 0)
    end

    test "has ref() → hybrid (client JS generated)" do
      assert function_exported?(HybridLive, :__hybrid_client_js__, 0)
    end
  end
end
