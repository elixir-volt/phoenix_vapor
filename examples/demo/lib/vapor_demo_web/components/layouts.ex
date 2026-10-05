defmodule VaporDemoWeb.Layouts do
  @moduledoc "The demo's layouts: the HTML document, and the app shell every page renders in."

  use VaporDemoWeb, :html

  embed_templates "layouts/*"

  @workspace [{"Contacts", "/contacts"}, {"Settings", "/settings"}]

  @modes [
    {"~VUE sigil", "/modes/sigil"},
    {"Server-only .vue", "/modes/server"},
    {"Reactive", "/modes/reactive"},
    {"Hybrid", "/modes/hybrid"},
    {"Full runtime", "/modes/full"},
    {"HEEx vs Vue", "/modes/compare"}
  ]

  @doc "The app shell: navigation, the page, and flash messages."
  def app(assigns) do
    assigns = assign(assigns, workspace: @workspace, modes: @modes)

    ~H"""
    <div class="min-h-screen bg-zinc-50 text-zinc-900">
      <header class="border-b border-zinc-200 bg-white">
        <nav class="mx-auto flex max-w-5xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3 text-sm">
          <.link navigate="/" class="font-semibold">PhoenixVapor demo</.link>
          <span class="flex gap-4">
            <.link
              :for={{label, path} <- @workspace}
              navigate={path}
              class="text-zinc-600 hover:text-zinc-900"
            >
              {label}
            </.link>
          </span>
          <span class="flex flex-wrap gap-3 text-zinc-500">
            <span class="text-zinc-400">Modes:</span>
            <.link :for={{label, path} <- @modes} navigate={path} class="hover:text-zinc-900">
              {label}
            </.link>
          </span>
        </nav>
      </header>

      <main class="mx-auto max-w-5xl px-4 py-8">
        {@inner_content}
      </main>

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="disconnected"
        kind={:error}
        title="Reconnecting"
        phx-disconnected={show("#disconnected")}
        phx-connected={hide("#disconnected")}
        hidden
      >
        The connection to the server was lost.
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
