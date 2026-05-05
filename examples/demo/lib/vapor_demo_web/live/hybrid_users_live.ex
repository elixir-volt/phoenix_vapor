defmodule VaporDemoWeb.HybridUsersLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "HybridUsers.vue"

  @users [
    %{id: 1, name: "Alice Chen", email: "alice@example.com"},
    %{id: 2, name: "Bob Smith", email: "bob@example.com"},
    %{id: 3, name: "Carol Davis", email: "carol@example.com"},
    %{id: 4, name: "Dave Wilson", email: "dave@example.com"},
    %{id: 5, name: "Eve Johnson", email: "eve@example.com"},
    %{id: 6, name: "Frank Brown", email: "frank@example.com"},
    %{id: 7, name: "Grace Lee", email: "grace@example.com"},
    %{id: 8, name: "Hank Miller", email: "hank@example.com"}
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, users: @users, title: "Hybrid Users")}
  end

  def handle_event("deleteUser", %{"id" => id}, socket) do
    users = Enum.reject(socket.assigns.users, &(&1.id == id))
    {:noreply, assign(socket, users: users)}
  end
end
