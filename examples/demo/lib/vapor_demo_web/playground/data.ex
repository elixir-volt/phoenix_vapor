defmodule VaporDemoWeb.Playground.Data do
  @moduledoc false

  def project, do: %{name: "Acme Dashboard", plan: "pro"}

  def members do
    [
      %{id: 1, name: "Alice Chen", email: "alice@acme.co", role: "owner", active: true},
      %{id: 2, name: "Bob Smith", email: "bob@acme.co", role: "admin", active: true},
      %{id: 3, name: "Carol Davis", email: "carol@acme.co", role: "member", active: true},
      %{id: 4, name: "Dave Wilson", email: "dave@acme.co", role: "member", active: false},
      %{id: 5, name: "Eve Johnson", email: "eve@acme.co", role: "admin", active: true}
    ]
  end
end
