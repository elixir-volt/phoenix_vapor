defmodule VaporDemoWeb.Layouts do
  @moduledoc "The demo's layouts: the HTML document, and the app shell every page renders in."

  use VaporDemoWeb, :html

  embed_templates "layouts/*"

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
