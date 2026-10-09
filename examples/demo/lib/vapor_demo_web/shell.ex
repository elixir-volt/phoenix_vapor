defmodule VaporDemoWeb.Shell do
  @moduledoc """
  The app shell every page renders in: the sidebar, written as a `~VUE`
  template, and the `on_mount` hook that keeps what it shows current.

  The hook assigns `:shell` (the teams with their open issue counts, and the
  page's path) and refreshes it whenever the tracker changes. It also handles
  "reset_demo" from the sidebar on every page.
  """

  use Phoenix.Component

  import PhoenixVapor.Sigil
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, put_flash: 3]

  alias VaporDemo.Tracker

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Tracker.subscribe()

    socket =
      socket
      |> assign(shell: shell(nil))
      |> attach_hook(:shell_path, :handle_params, fn _params, url, socket ->
        {:cont, assign(socket, shell: shell(URI.parse(url).path))}
      end)
      |> attach_hook(:shell_changes, :handle_info, fn
        :tracker_changed, socket -> {:cont, assign(socket, shell: shell(socket.assigns.shell.path))}
        _message, socket -> {:cont, socket}
      end)
      |> attach_hook(:shell_reset, :handle_event, fn
        "reset_demo", _params, socket ->
          Tracker.reset()
          {:halt, put_flash(socket, :info, "The demo is back to its first state.")}

        _event, _params, socket ->
          {:cont, socket}
      end)

    {:cont, socket}
  end

  defp shell(path) do
    me = Tracker.me()

    teams =
      for team <- Tracker.teams() do
        issues = Tracker.issues(team.key)
        open = Enum.count(issues, &(&1.status != "done"))

        %{
          key: team.key,
          name: team.name,
          links: [
            link("Board", "/#{team.key}/board", "hero-view-columns", nil, path),
            link("Issues", "/#{team.key}/issues", "hero-queue-list", open, path)
          ]
        }
      end

    mine =
      Tracker.teams()
      |> Enum.flat_map(&Tracker.issues(&1.key))
      |> Enum.count(&(&1.assignee_id == me.id and &1.status != "done"))

    %{
      path: path,
      me: me,
      links: [link("My issues", "/my-issues", "hero-user-circle", mine, path)],
      teams: teams
    }
  end

  defp link(label, href, icon, count, path),
    do: %{label: label, href: href, icon: icon, count: count, active: href == path}

  @doc "The sidebar: the workspace, search, navigation and the demo's switches."
  attr :shell, :map, required: true
  attr :dev, :boolean, default: false

  def sidebar(assigns) do
    ~VUE"""
    <aside
      data-render="server"
      data-render-label="~VUE sigil · server"
      class="sticky top-0 flex h-screen w-60 shrink-0 flex-col gap-5 border-r border-line px-2.5 py-3.5 max-md:hidden"
    >
      <div class="flex items-center gap-2.5 px-1.5 py-1">
        <span class="grid size-[22px] place-items-center rounded-md bg-accent text-xs font-semibold text-accent-fg">A</span>
        <span class="text-[13.5px] font-semibold">Acme</span>
        <span class="ml-auto text-xs text-faint">Tracker</span>
      </div>

      <button
        type="button"
        data-action="palette"
        class="flex h-8 items-center gap-2 rounded-md border border-edge bg-panel px-2.5 text-left text-muted hover:text-fg-2"
      >
        <span class="hero-magnifying-glass size-3.5"></span>
        <span>Search or jump to…</span>
        <kbd class="ml-auto rounded border border-edge px-1 font-mono text-[11px] text-faint">⌘K</kbd>
      </button>

      <nav aria-label="You" class="flex flex-col gap-px">
        <a
          v-for="item in shell.links"
          :key="item.href"
          :href="item.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="flex h-[30px] items-center gap-2.5 rounded-md px-2.5 hover:bg-raised"
          :class="item.active ? 'bg-raised text-fg' : 'text-fg-2'"
        >
          <span :class="item.icon" class="size-4 text-muted"></span>
          {{ item.label }}
          <span v-if="item.count" class="ml-auto text-xs text-faint">{{ item.count }}</span>
        </a>
      </nav>

      <nav v-for="team in shell.teams" :key="team.key" :aria-label="team.name" class="flex flex-col gap-px">
        <span class="px-2.5 pb-1.5 text-[11.5px] font-medium text-faint">{{ team.name }}</span>
        <a
          v-for="item in team.links"
          :key="item.href"
          :href="item.href"
          data-phx-link="redirect"
          data-phx-link-state="push"
          class="flex h-[30px] items-center gap-2.5 rounded-md px-2.5 hover:bg-raised"
          :class="item.active ? 'bg-raised text-fg' : 'text-fg-2'"
        >
          <span :class="item.icon" class="size-4 text-muted"></span>
          {{ item.label }}
          <span v-if="item.count" class="ml-auto text-xs text-faint">{{ item.count }}</span>
        </a>
      </nav>

      <div class="mt-auto flex flex-col gap-1.5">
        <button
          type="button"
          data-action="xray"
          class="flex h-[34px] items-center gap-2.5 rounded-md border border-edge bg-panel px-2.5 text-fg hover:bg-raised"
        >
          <span class="hero-viewfinder-circle size-4 text-muted"></span>
          X-ray
          <span class="xray-off ml-auto text-[11.5px] text-faint">Off</span>
          <span class="xray-on ml-auto text-[11.5px] text-[#3dd68c]">On</span>
          <kbd class="rounded border border-edge px-1 font-mono text-[11px] text-faint">X</kbd>
        </button>
        <div class="flex items-center gap-1 px-1 text-[11.5px] text-faint">
          <button type="button" data-action="theme" class="rounded px-1.5 py-1 hover:bg-raised hover:text-fg-2">Theme</button>
          <button type="button" phx-click="reset_demo" class="rounded px-1.5 py-1 hover:bg-raised hover:text-fg-2">Reset demo</button>
          <a v-if="dev" href="/dev/replay" target="_blank" class="ml-auto rounded px-1.5 py-1 text-link hover:bg-raised">Replays</a>
        </div>
      </div>
    </aside>
    """
  end
end
