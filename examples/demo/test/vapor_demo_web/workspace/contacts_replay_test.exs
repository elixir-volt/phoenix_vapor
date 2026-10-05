defmodule VaporDemoWeb.Workspace.ContactsReplayTest do
  use ExUnit.Case, async: true

  alias VaporDemoWeb.Workspace.ContactsLive

  @contacts [
    %{
      id: 1,
      name: "Alice Chen",
      email: "alice@acme.co",
      company: "Acme Corp",
      role: "Lead",
      initials: "AC"
    },
    %{
      id: 2,
      name: "Bob Smith",
      email: "bob@initech.com",
      company: "Initech",
      role: "Admin",
      initials: "BS"
    },
    %{
      id: 3,
      name: "Carol Davis",
      email: "carol@acme.co",
      company: "Acme Corp",
      role: "Designer",
      initials: "CD"
    }
  ]

  defp html(rendered), do: rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  defp names(html),
    do: Regex.scan(~r/font-medium text-zinc-900">([^<]+)</, html) |> Enum.map(&List.last/1)

  test "the live render lists every contact by name" do
    html = ContactsLive.render(%{contacts: @contacts, __changed__: nil}) |> html()

    assert html =~ "3 of 3 contacts"
    assert names(html) == ["Alice Chen", "Carol Davis", "Bob Smith"]
  end

  test "a replay renders the recorded search and sort order" do
    state = %{"phoenix_vapor:pv-Contacts" => %{"search" => "acme", "sortKey" => "role"}}

    html =
      %{contacts: @contacts, phoenix_replay_state: state, __changed__: nil}
      |> ContactsLive.replay_render()
      |> html()

    assert html =~ "2 of 3 contacts"
    # Designer before Lead.
    assert names(html) == ["Carol Davis", "Alice Chen"]
  end

  test "a recorded sort key the server doesn't know sorts by name" do
    state = %{"phoenix_vapor:pv-Contacts" => %{"search" => "", "sortKey" => "password"}}

    html =
      %{contacts: @contacts, phoenix_replay_state: state, __changed__: nil}
      |> ContactsLive.replay_render()
      |> html()

    assert names(html) == ["Alice Chen", "Carol Davis", "Bob Smith"]
  end
end
