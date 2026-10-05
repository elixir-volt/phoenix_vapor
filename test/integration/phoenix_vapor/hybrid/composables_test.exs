defmodule PhoenixVapor.Integration.Hybrid.ComposablesTest do
  # Ordinary Vue code: composables from VueUse and functions from es-toolkit,
  # which only the browser has.
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias PhoenixVapor.Fixtures

  @contacts [%{"name" => "Bob"}, %{"name" => "Ada"}, %{"name" => "Cy"}]

  defp html(rendered), do: rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  setup_all do
    warnings =
      capture_io(:stderr, fn ->
        Code.compile_quoted(
          quote do
            defmodule PhoenixVapor.Integration.Hybrid.ComposablesTest.ContactsLive do
              use Phoenix.LiveView

              use PhoenixVapor,
                file: unquote(Fixtures.path("HybridComposables.vue")),
                client_output: nil
            end
          end
        )
      end)

    %{warnings: warnings}
  end

  test "warns about each computed the server can't evaluate, naming what it lacks",
       %{warnings: warnings} do
    assert warnings =~ "computed `matching` reads `debouncedSearch`, which only the browser has"
    assert warnings =~ "computed `names` reads `sortBy`, which only the browser has"
    refute warnings =~ "computed `total`"
  end

  test "renders the first paint without what reads them" do
    html = __MODULE__.ContactsLive.render(%{contacts: @contacts, __changed__: nil}) |> html()

    # A computed of props renders.
    assert html =~ "3 contacts"
    # A v-if chain whose condition reads a left-out computed renders no
    # branch: neither "No contacts match" nor a count of matches.
    refute html =~ "match"
    # Nor does a v-for over one.
    refute html =~ "<li>"
  end
end
