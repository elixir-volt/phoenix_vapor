defmodule LiveVueNextDemoWeb.TodoLive do
  use LiveVueNextDemoWeb, :live_view
  use LiveVueNext

  def mount(_params, _session, socket) do
    todos = [
      %{id: 1, text: "Build live_vue_next", done: true},
      %{id: 2, text: "Create demo app", done: true},
      %{id: 3, text: "Ship it", done: false}
    ]

    {:ok, assign(socket, todos: todos, new_todo: "", next_id: 4, filter: "all")}
  end

  def render(assigns) do
    ~VUE"""
    <div class="space-y-4">
      <h2 class="text-2xl font-bold">Todo List</h2>

      <form phx-submit="add" class="flex gap-2">
        <input type="text" name="text" phx-change="update_input" class="flex-1 px-3 py-2 border rounded" placeholder="What needs to be done?" />
        <button type="submit" class="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600">Add</button>
      </form>

      <div class="flex gap-2 text-sm">
        <button phx-click="filter" phx-value-filter="all" :class="filter === 'all' ? 'font-bold underline' : 'text-gray-500'">All</button>
        <button phx-click="filter" phx-value-filter="active" :class="filter === 'active' ? 'font-bold underline' : 'text-gray-500'">Active</button>
        <button phx-click="filter" phx-value-filter="done" :class="filter === 'done' ? 'font-bold underline' : 'text-gray-500'">Done</button>
      </div>

      <ul class="space-y-2">
        <li v-for="todo in todos" class="flex items-center gap-2 p-2 border rounded">
          <input type="checkbox" phx-click="toggle" :phx-value-id="todo.id" />
          <span :class="todo.done ? 'line-through text-gray-400' : ''">{{ todo.text }}</span>
          <button phx-click="delete" :phx-value-id="todo.id" class="ml-auto text-red-400 hover:text-red-600">✕</button>
        </li>
      </ul>

      <p class="text-sm text-gray-500" v-if="todos.length === 0">No todos yet. Add one above!</p>
    </div>
    """
  end

  def handle_event("add", %{"text" => text}, socket) when text != "" do
    todo = %{id: socket.assigns.next_id, text: text, done: false}

    {:noreply,
     socket
     |> update(:todos, &(&1 ++ [todo]))
     |> update(:next_id, &(&1 + 1))
     |> assign(:new_todo, "")}
  end

  def handle_event("add", _, socket), do: {:noreply, socket}

  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)

    todos =
      Enum.map(socket.assigns.todos, fn
        %{id: ^id} = todo -> %{todo | done: !todo.done}
        todo -> todo
      end)

    {:noreply, assign(socket, todos: filter_todos(todos, socket.assigns.filter))}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id = String.to_integer(id)
    todos = Enum.reject(socket.assigns.todos, &(&1.id == id))
    {:noreply, assign(socket, todos: todos)}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    {:noreply, assign(socket, filter: filter, todos: filter_todos(all_todos(socket), filter))}
  end

  def handle_event("update_input", %{"text" => text}, socket) do
    {:noreply, assign(socket, new_todo: text)}
  end

  defp all_todos(socket), do: socket.assigns.todos

  defp filter_todos(todos, "active"), do: Enum.filter(todos, &(!&1.done))
  defp filter_todos(todos, "done"), do: Enum.filter(todos, & &1.done)
  defp filter_todos(todos, _), do: todos
end
