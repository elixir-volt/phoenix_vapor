defmodule VaporDemo.Contacts do
  @moduledoc """
  The workspace's contacts, kept in memory for the demo and broadcast on every
  change, so every open page shows the same list.
  """

  use Agent

  @topic "contacts"

  @seed [
    {"Alice Chen", "alice@acme.co", "Acme Corp", "Engineering Lead"},
    {"Bob Smith", "bob@initech.com", "Initech", "Product Manager"},
    {"Carol Davis", "carol@globex.io", "Globex", "Designer"},
    {"Dave Wilson", "dave@acme.co", "Acme Corp", "Backend Engineer"},
    {"Eve Johnson", "eve@initech.com", "Initech", "Frontend Engineer"},
    {"Frank Brown", "frank@globex.io", "Globex", "DevOps"},
    {"Grace Lee", "grace@hooli.com", "Hooli", "Data Scientist"},
    {"Hank Miller", "hank@piedpiper.com", "Pied Piper", "CTO"},
    {"Iris Wang", "iris@hooli.com", "Hooli", "ML Engineer"},
    {"Jack Taylor", "jack@piedpiper.com", "Pied Piper", "Engineer"},
    {"Karen White", "karen@acme.co", "Acme Corp", "QA Lead"},
    {"Leo Martinez", "leo@globex.io", "Globex", "Architect"}
  ]

  def start_link(_opts), do: Agent.start_link(&seed/0, name: __MODULE__)

  @doc "All contacts, in the order they were added."
  def list, do: Agent.get(__MODULE__, & &1)

  @doc "Deletes the contacts with `ids` and tells every subscriber."
  def delete(ids) when is_list(ids), do: update(&Enum.reject(&1, fn c -> c.id in ids end))

  @doc "Restores the seed contacts, as the demo starts with them."
  def reset, do: update(fn _contacts -> seed() end)

  @doc "Subscribes the caller to `{:contacts, contacts}` on every change."
  def subscribe, do: Phoenix.PubSub.subscribe(VaporDemo.PubSub, @topic)

  defp update(fun) do
    contacts =
      Agent.get_and_update(__MODULE__, fn contacts ->
        contacts = fun.(contacts)
        {contacts, contacts}
      end)

    Phoenix.PubSub.broadcast(VaporDemo.PubSub, @topic, {:contacts, contacts})
    contacts
  end

  # The initials are data, so templates don't compute them.
  defp seed do
    for {{name, email, company, role}, id} <- Enum.with_index(@seed, 1) do
      initials = name |> String.split() |> Enum.map_join(&String.first/1)
      %{id: id, name: name, email: email, company: company, role: role, initials: initials}
    end
  end
end
