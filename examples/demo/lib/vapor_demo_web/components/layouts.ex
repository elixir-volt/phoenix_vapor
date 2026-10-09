defmodule VaporDemoWeb.Layouts do
  @moduledoc "The demo's layouts: the HTML document, and the app shell every page renders in."

  use VaporDemoWeb, :html

  embed_templates "layouts/*"

  @doc """
  The x-ray's legend and source drawer, shown while it's on. The page's
  script fills the drawer, so LiveView leaves it alone.
  """
  attr :dev, :boolean, required: true

  def xray(assigns) do
    ~H"""
    <aside
      aria-label="How this page renders"
      class="xray-legend fixed bottom-5 right-5 z-40 w-72 flex-col gap-2.5 rounded-xl border border-edge bg-panel/95 p-4 text-[12.5px] shadow-2xl shadow-black/50"
    >
      <span class="font-semibold text-fg">How this page renders</span>
      <span
        :for={
          {kind, color, text} <- [
            {"server", "#4c9bff", "Server: HTML from Elixir, no JavaScript"},
            {"hybrid", "#3dd68c", "Hybrid: Vue runs it in the browser"},
            {"folded", "#f5a524", "Folded: rendered while compiling"},
            {"reactive", "#b48cff", "Reactive: Vue's reactivity on the server"}
          ]
        }
        class="flex items-center gap-2 text-fg-2"
      >
        <span class="size-2.5 rounded-[3px] border-[1.5px]" style={"border-color: #{color}"} data-kind={kind}></span>
        {text}
      </span>
      <span class="border-t border-line pt-2.5 text-faint">
        Click a region to see its source.
        <a :if={@dev} href="/dev/replay" target="_blank" class="text-link">Replays →</a>
      </span>
    </aside>

    <div id="xray-source" phx-update="ignore" hidden class="fixed inset-y-0 right-0 z-50 flex w-[min(680px,100vw)] flex-col border-l border-edge bg-panel shadow-2xl shadow-black/60">
      <header class="flex items-center gap-3 border-b border-line px-4 py-3">
        <code data-path class="font-mono text-[12.5px] text-fg"></code>
        <button type="button" data-action="close-source" class="ml-auto rounded-md px-2 py-1 text-muted hover:bg-raised hover:text-fg">
          Close <kbd class="font-mono text-[11px]">esc</kbd>
        </button>
      </header>
      <pre data-source class="min-h-0 flex-1 overflow-auto p-4 font-mono text-[12px] leading-relaxed text-fg-2"></pre>
    </div>
    """
  end

  @doc "The app shell: the sidebar, the page, and flash messages."
  def app(assigns) do
    assigns = assign(assigns, dev: Application.get_env(:vapor_demo, :dev_routes, false))

    ~H"""
    <div class="flex min-h-screen bg-bg font-sans text-[13px] leading-[1.45] text-fg">
      <VaporDemoWeb.Shell.sidebar shell={@shell} dev={@dev} />

      <main class="flex min-w-0 flex-1 flex-col">
        {@inner_content}
      </main>

      <VaporDemoWeb.Activity.rail :if={assigns[:activity]} entries={@activity} />

      {live_render(@socket, VaporDemoWeb.Palette.PaletteLive, id: "palette", sticky: true)}

      <.xray dev={@dev} />

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
