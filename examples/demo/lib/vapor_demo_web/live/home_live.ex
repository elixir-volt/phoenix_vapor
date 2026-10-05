defmodule VaporDemoWeb.HomeLive do
  @moduledoc "The demo's front page: the workspace, and the modes gallery."

  use VaporDemoWeb, :live_view
  use PhoenixVapor

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Home",
       workspace: [
         %{
           title: "Contacts",
           path: "/contacts",
           desc:
             "Search, sort and select in the browser, with es-toolkit and VueUse; delete through the server, and every open tab follows."
         },
         %{
           title: "Settings",
           path: "/settings",
           desc:
             "Reka UI tabs, a select and a dialog; rename the project or remove a member through the server."
         }
       ],
       modes: [
         %{
           title: "~VUE sigil",
           path: "/modes/sigil",
           desc: "Vue syntax in a LiveView, in place of HEEx."
         },
         %{
           title: "Server-only .vue",
           path: "/modes/server",
           desc: "A .vue file with props, rendered by the server alone."
         },
         %{
           title: "Reactive",
           path: "/modes/reactive",
           desc: "A LiveView that is one .vue file, its state on the server."
         },
         %{
           title: "Hybrid",
           path: "/modes/hybrid",
           desc: "State in the browser, data on the server."
         },
         %{
           title: "Full runtime",
           path: "/modes/full",
           desc: "Vue itself renders a component library on the server."
         },
         %{
           title: "HEEx vs Vue",
           path: "/modes/compare",
           desc: "The same template in both syntaxes."
         }
       ]
     )}
  end

  def render(assigns) do
    ~VUE"""
    <div class="space-y-10">
      <header>
        <h1 class="text-3xl font-bold tracking-tight">PhoenixVapor</h1>
        <p class="mt-1 text-zinc-500">
          Vue templates and single-file components for Phoenix LiveView, rendered on the server in Elixir.
        </p>
      </header>

      <section class="space-y-3">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Workspace</h2>
        <div class="grid gap-3 sm:grid-cols-2">
          <a v-for="page in workspace" :key="page.path" :href="page.path" data-phx-link="redirect" data-phx-link-state="push" class="block rounded-lg border border-zinc-200 bg-white p-5 hover:border-zinc-400">
            <h3 class="text-lg font-semibold">{{ page.title }}</h3>
            <p class="mt-1 text-sm text-zinc-500">{{ page.desc }}</p>
          </a>
        </div>
      </section>

      <section class="space-y-3">
        <h2 class="text-sm font-semibold uppercase tracking-wide text-zinc-400">Modes</h2>
        <ul class="divide-y divide-zinc-100 rounded-lg border border-zinc-200 bg-white">
          <li v-for="mode in modes" :key="mode.path">
            <a :href="mode.path" data-phx-link="redirect" data-phx-link-state="push" class="flex items-baseline gap-3 px-4 py-3 hover:bg-zinc-50">
              <span class="font-medium">{{ mode.title }}</span>
              <span class="text-sm text-zinc-500">{{ mode.desc }}</span>
            </a>
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
