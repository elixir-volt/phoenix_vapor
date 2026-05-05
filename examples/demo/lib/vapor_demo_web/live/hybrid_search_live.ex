defmodule VaporDemoWeb.HybridSearchLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor.Hybrid, file: "HybridSearch.vue"

  @contacts [
    %{id: 1, name: "Alice Chen", email: "alice@acme.co", company: "Acme Corp"},
    %{id: 2, name: "Bob Smith", email: "bob@initech.com", company: "Initech"},
    %{id: 3, name: "Carol Davis", email: "carol@globex.io", company: "Globex"},
    %{id: 4, name: "Dave Wilson", email: "dave@acme.co", company: "Acme Corp"},
    %{id: 5, name: "Eve Johnson", email: "eve@initech.com", company: "Initech"},
    %{id: 6, name: "Frank Brown", email: "frank@globex.io", company: "Globex"},
    %{id: 7, name: "Grace Lee", email: "grace@hooli.com", company: "Hooli"},
    %{id: 8, name: "Hank Miller", email: "hank@piedpiper.com", company: "Pied Piper"},
    %{id: 9, name: "Iris Wang", email: "iris@hooli.com", company: "Hooli"},
    %{id: 10, name: "Jack Taylor", email: "jack@piedpiper.com", company: "Pied Piper"},
    %{id: 11, name: "Karen White", email: "karen@acme.co", company: "Acme Corp"},
    %{id: 12, name: "Leo Martinez", email: "leo@globex.io", company: "Globex"}
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, contacts: @contacts, title: "Contacts")}
  end
end
