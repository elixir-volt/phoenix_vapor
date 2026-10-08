defmodule PhoenixVapor.Integration.Hybrid.ComposablesTest do
  # Ordinary Vue code: composables from VueUse and functions from es-toolkit,
  # which only the browser has.
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias PhoenixVapor.Fixtures

  @contacts [%{"name" => "Bob"}, %{"name" => "Ada"}, %{"name" => "Cy"}]

  defp html(rendered), do: rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  setup_all do
    %{
      warnings: compile(:ContactsLive, "HybridComposables.vue"),
      twin_warnings: compile(:TwinsLive, "HybridComposablesTwins.vue")
    }
  end

  # Compiles a hybrid LiveView from a fixture, returning the warnings.
  defp compile(name, fixture) do
    module = Module.concat(__MODULE__, name)

    capture_io(:stderr, fn ->
      Code.compile_quoted(
        quote do
          defmodule unquote(module) do
            use Phoenix.LiveView
            use PhoenixVapor, file: unquote(Fixtures.path(fixture)), client_output: nil
          end
        end
      )
    end)
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

  describe "with Elixir counterparts" do
    test "the server computes them in Elixir, and renders what reads them",
         %{twin_warnings: warnings} do
      refute warnings =~ "computed `matching`"
      refute warnings =~ "computed `names`"

      html = __MODULE__.TwinsLive.render(%{contacts: @contacts, __changed__: nil}) |> html()

      assert html =~ "3 match"
      assert html =~ "<li>Ada</li><li>Bob</li><li>Cy</li>"
    end

    test "constants and script functions with counterparts are known to the server",
         %{twin_warnings: warnings} do
      refute warnings =~ "computed `firstPage`"
      refute warnings =~ "computed `firstInitial`"

      html = __MODULE__.TwinsLive.render(%{contacts: @contacts, __changed__: nil}) |> html()

      assert html =~ "first page: Bob, Ada, of 2"
      assert html =~ "initial: B"
    end

    test "warns about a counterpart that requires state only the browser has",
         %{twin_warnings: warnings} do
      assert warnings =~ "`sorted/1` requires `sortKey`, which only the browser has"
      assert warnings =~ "HybridComposablesTwins.vue:42"
      # matching/1 requires search, a ref, and themed/1 reads theme as optional.
      refute warnings =~ "`matching/1`"
      refute warnings =~ "`themed/1`"
    end

    test "a counterpart reading state as assigns[:key] renders live and in a replay" do
      html = __MODULE__.TwinsLive.render(%{contacts: @contacts, __changed__: nil}) |> html()
      assert html =~ "themed: Bob:light, Ada:light, Cy:light"

      state = %{"phoenix_vapor:pv-HybridComposablesTwins" => %{"theme" => "dark"}}

      replayed =
        %{contacts: @contacts, phoenix_replay_state: state, __changed__: nil}
        |> __MODULE__.TwinsLive.replay_render()
        |> html()

      assert replayed =~ "themed: Bob:dark, Ada:dark, Cy:dark"
    end

    test "a counterpart reading composable state waits for its value, as what reads it does" do
      html = __MODULE__.TwinsLive.render(%{contacts: @contacts, __changed__: nil}) |> html()

      # sortKey comes from useLocalStorage: the live render doesn't have it,
      # so sorted/1 isn't called and the v-if chain renders no branch.
      refute html =~ "<ol><li>"
      refute html =~ "by name"
      refute html =~ "by something else"

      state = %{"phoenix_vapor:pv-HybridComposablesTwins" => %{"sortKey" => "name"}}

      replayed =
        %{contacts: @contacts, phoenix_replay_state: state, __changed__: nil}
        |> __MODULE__.TwinsLive.replay_render()
        |> html()

      assert replayed =~ "<ol><li>Ada</li><li>Bob</li><li>Cy</li></ol>"
      assert replayed =~ "by name"
    end

    test "a replay computes them from the recorded refs" do
      state = %{"phoenix_vapor:pv-HybridComposablesTwins" => %{"search" => "y"}}

      html =
        %{contacts: @contacts, phoenix_replay_state: state, __changed__: nil}
        |> __MODULE__.TwinsLive.replay_render()
        |> html()

      assert html =~ "1 match"
    end
  end

  test "a computed named after a LiveView callback can't have an Elixir counterpart" do
    error =
      assert_raise CompileError, fn ->
        Code.compile_quoted(
          quote do
            defmodule PhoenixVapor.Integration.Hybrid.ComposablesTest.ReservedLive do
              use Phoenix.LiveView

              use PhoenixVapor,
                file: unquote(Fixtures.path("HybridReservedTwin.vue")),
                client_output: nil
            end
          end
        )
      end

    assert Exception.message(error) =~ "`render` is a LiveView callback"
  end

  describe "recording" do
    @tag :tmp_dir
    test "a replay renders recorded state on a server that didn't compile the component",
         %{tmp_dir: tmp_dir} do
      # A replay looks each recorded name's atom up, never creating one, so
      # the module itself must carry it: a server running a release didn't
      # compile the component, and an atom made while compiling doesn't
      # exist there.
      [{module, binary}] =
        Code.compile_quoted(
          quote do
            defmodule PhoenixVapor.Integration.Hybrid.ComposablesTest.RecordedOnlyLive do
              use Phoenix.LiveView

              use PhoenixVapor,
                file: unquote(Fixtures.path("HybridRecordedOnly.vue")),
                client_output: nil
            end
          end
        )

      assert module.__hybrid_client_js__() =~ "record({ clipboardWasCopied })"
      File.write!(Path.join(tmp_dir, "#{module}.beam"), binary)

      script = """
      state = %{"phoenix_vapor:pv-HybridRecordedOnly" => %{"clipboardWasCopied" => true}}

      %{count: 2, phoenix_replay_state: state, __changed__: nil}
      |> #{inspect(module)}.replay_render()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()
      |> IO.write()
      """

      paths = Enum.flat_map([tmp_dir | :code.get_path()], &["-pa", to_string(&1)])
      {html, 0} = System.cmd("elixir", paths ++ ["-e", script], stderr_to_stdout: true)

      assert html =~ "<p>Copied 4</p>"
    end

    test "registers only the client state the render reads, through computeds too" do
      js = __MODULE__.ContactsLive.__hybrid_client_js__()

      # The template reads search and sortKey. debouncedSearch feeds only a
      # computed the server leaves out, and nothing reads useMouse's x and y.
      assert js =~ "__pv?.record({ search, sortKey });"
    end

    test "a replay renders recorded composable state" do
      state = %{"phoenix_vapor:pv-HybridComposables" => %{"sortKey" => "email"}}

      html =
        %{contacts: @contacts, phoenix_replay_state: state, __changed__: nil}
        |> __MODULE__.ContactsLive.replay_render()
        |> html()

      assert html =~ "sorted by email"
    end

    test "an Elixir counterpart's reads are recorded, optional ones too" do
      # matching's counterpart reads search, and themed's reads theme, which
      # nothing else reads.
      js = __MODULE__.TwinsLive.__hybrid_client_js__()
      assert js =~ "__pv?.record({ search, sortKey, theme });"
    end
  end
end
