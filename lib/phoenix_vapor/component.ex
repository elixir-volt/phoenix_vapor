defmodule PhoenixVapor.Component do
  @moduledoc """
  Helpers for using Vue templates in Phoenix components.

  ## Usage in a LiveView

      defmodule MyAppWeb.DashboardLive do
        use MyAppWeb, :live_view
        import PhoenixVapor.Component

        def mount(_params, _session, socket) do
          {:ok, assign(socket, items: [], title: "Dashboard")}
        end

        def render(assigns) do
          vue ~VUE\"""
          <div>
            <h1>{{ title }}</h1>
            <ul>
              <li v-for="item in items">{{ item.name }}</li>
            </ul>
          </div>
          \"""
        end
      end

  ## Usage in a function component

      defmodule MyAppWeb.Components do
        use Phoenix.Component
        import PhoenixVapor.Component

        def card(assigns) do
          vue ~VUE\"""
          <div :class="variant">
            <h2>{{ title }}</h2>
            <p>{{ description }}</p>
          </div>
          \"""
        end
      end
  """

  @doc """
  Wraps a `%Rendered{}` struct produced by `~VUE` to ensure it works
  as the return value of a `render/1` or function component.

  This is a pass-through — the `~VUE` sigil already produces a valid
  `%Rendered{}`. This function exists for clarity and future hooks
  (e.g., adding component-level metadata).
  """
  defmacro vue(rendered) do
    rendered
  end
end
