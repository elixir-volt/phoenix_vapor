defmodule VaporDemoWeb.HybridContactsLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor.Hybrid, file: "HybridContacts.vue"

  @colors ~w(bg-blue-500 bg-green-500 bg-purple-500 bg-orange-500 bg-pink-500 bg-teal-500 bg-indigo-500 bg-red-500 bg-cyan-500 bg-amber-500)

  @contacts [
    %{id: 1, name: "Alice Chen", email: "alice@acme.co", company: "Acme Corp", role: "Engineering Lead", color: "bg-blue-500"},
    %{id: 2, name: "Bob Smith", email: "bob@initech.com", company: "Initech", role: "Product Manager", color: "bg-green-500"},
    %{id: 3, name: "Carol Davis", email: "carol@globex.io", company: "Globex", role: "Designer", color: "bg-purple-500"},
    %{id: 4, name: "Dave Wilson", email: "dave@acme.co", company: "Acme Corp", role: "Backend Dev", color: "bg-orange-500"},
    %{id: 5, name: "Eve Johnson", email: "eve@initech.com", company: "Initech", role: "Frontend Dev", color: "bg-pink-500"},
    %{id: 6, name: "Frank Brown", email: "frank@globex.io", company: "Globex", role: "DevOps", color: "bg-teal-500"},
    %{id: 7, name: "Grace Lee", email: "grace@hooli.com", company: "Hooli", role: "Data Scientist", color: "bg-indigo-500"},
    %{id: 8, name: "Hank Miller", email: "hank@piedpiper.com", company: "Pied Piper", role: "CTO", color: "bg-red-500"},
    %{id: 9, name: "Iris Wang", email: "iris@hooli.com", company: "Hooli", role: "ML Engineer", color: "bg-cyan-500"},
    %{id: 10, name: "Jack Taylor", email: "jack@piedpiper.com", company: "Pied Piper", role: "Engineer", color: "bg-amber-500"},
    %{id: 11, name: "Karen White", email: "karen@acme.co", company: "Acme Corp", role: "QA Lead", color: "bg-blue-500"},
    %{id: 12, name: "Leo Martinez", email: "leo@globex.io", company: "Globex", role: "Architect", color: "bg-green-500"}
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, contacts: @contacts)}
  end

  def handle_event("deleteContact", %{"id" => id}, socket) do
    contacts = Enum.reject(socket.assigns.contacts, &(&1.id == id))
    {:noreply, assign(socket, contacts: contacts)}
  end

  def handle_event("deleteSelected", params, socket) do
    ids =
      case params do
        %{"selectedIds" => ids} when is_list(ids) -> ids
        _ -> []
      end

    contacts = Enum.reject(socket.assigns.contacts, &(&1.id in ids))
    {:noreply, assign(socket, contacts: contacts)}
  end
end
