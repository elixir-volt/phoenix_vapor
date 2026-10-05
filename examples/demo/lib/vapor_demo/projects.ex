defmodule VaporDemo.Projects do
  @moduledoc """
  The workspace's project and its members, kept in memory for the demo and
  broadcast on every change, so every open page shows the same project.
  """

  use Agent

  @topic "project"

  @members [
    {"Alice Chen", "alice@acme.co", "owner", true},
    {"Bob Smith", "bob@acme.co", "admin", true},
    {"Carol Davis", "carol@acme.co", "member", true},
    {"Dave Wilson", "dave@acme.co", "member", false},
    {"Eve Johnson", "eve@acme.co", "admin", true}
  ]

  def start_link(_opts), do: Agent.start_link(&seed/0, name: __MODULE__)

  @doc "The project, `%{name:, plan:}`."
  def project, do: Agent.get(__MODULE__, & &1.project)

  @doc "The project's members."
  def members, do: Agent.get(__MODULE__, & &1.members)

  @doc "Renames the project and tells every subscriber."
  def rename(name) when is_binary(name),
    do: update(&put_in(&1.project.name, String.trim(name)))

  @doc "Removes a member and tells every subscriber; the owner stays."
  def remove_member(id),
    do:
      update(
        &%{&1 | members: Enum.reject(&1.members, fn m -> m.id == id and m.role != "owner" end)}
      )

  @doc "Restores the seed project, as the demo starts with it."
  def reset, do: update(fn _ -> seed() end)

  @doc "Subscribes the caller to `{:project, project, members}` on every change."
  def subscribe, do: Phoenix.PubSub.subscribe(VaporDemo.PubSub, @topic)

  defp update(fun) do
    state =
      Agent.get_and_update(__MODULE__, fn state ->
        state = fun.(state)
        {state, state}
      end)

    Phoenix.PubSub.broadcast(VaporDemo.PubSub, @topic, {:project, state.project, state.members})
    state
  end

  defp seed do
    members =
      for {{name, email, role, active}, id} <- Enum.with_index(@members, 1),
          do: %{id: id, name: name, email: email, role: role, active: active}

    %{project: %{name: "Acme Dashboard", plan: "pro"}, members: members}
  end
end
