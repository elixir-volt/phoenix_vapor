defmodule PhoenixVapor.Compiler.PropTypes.Runtime do
  @moduledoc false

  # The QuickBEAM runtimes TypeScript runs in, one per install, which every
  # compile in the VM shares. The server starts the first time a compile asks,
  # under a fixed name, so compiles in parallel share one, and outlives the
  # compile that started it. A runtime that dies takes the server with it,
  # and the next compile starts both again.
  #
  # It lives until the VM exits, holding TypeScript and every file it parsed:
  # nothing in `mix compile`, and tens of megabytes through a long
  # `mix phx.server` session that recompiles, a fair price for checks that
  # take milliseconds instead of a second each.

  use GenServer

  alias PhoenixVapor.Compiler.PropTypes

  @doc """
  The runtime for the TypeScript install at `main`, started with `load` run
  in it the first time.
  """
  @spec fetch(Path.t(), (pid() -> :ok | {:error, String.t()})) ::
          {:ok, pid()} | {:error, String.t()}
  def fetch(main, load) do
    GenServer.call(server(), {:fetch, main, load}, :infinity)
  end

  defp server do
    case GenServer.start(__MODULE__, nil, name: __MODULE__) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  @impl GenServer
  def init(nil), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:fetch, main, load}, _from, runtimes) do
    case runtimes do
      %{^main => runtime} ->
        {:reply, {:ok, runtime}, runtimes}

      _none ->
        {:ok, runtime} = QuickBEAM.start(handlers: PropTypes.handlers())

        case load.(runtime) do
          :ok ->
            {:reply, {:ok, runtime}, Map.put(runtimes, main, runtime)}

          {:error, reason} ->
            QuickBEAM.stop(runtime)
            {:reply, {:error, reason}, runtimes}
        end
    end
  end
end
