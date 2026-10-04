defmodule PhoenixVapor.JS.Session do
  @moduledoc false

  # The QuickBEAM runtime one compile uses for macros, package components and
  # prop types: started when first needed, with each bundle loaded into it
  # once, and stopped by whoever opened the session, in an `after`, so a
  # compile error doesn't leak it. Its globals are namespaced `__pv_*`, so
  # the bundles share it.

  @enforce_keys [:agent]
  defstruct [:agent]

  @type t :: %__MODULE__{agent: pid()}

  @doc """
  Opens a session whose runtime gets `handlers` for `Beam.callSync`; nothing
  starts until `runtime/1` or `once/3`.
  """
  @spec open(map()) :: t()
  def open(handlers \\ %{}) do
    {:ok, agent} = Agent.start_link(fn -> %{runtime: nil, handlers: handlers, loaded: %{}} end)
    %__MODULE__{agent: agent}
  end

  @doc "Runs `fun` with a session, closing it afterwards, also when `fun` raises."
  @spec with_session(map(), (t() -> result)) :: result when result: term()
  def with_session(handlers \\ %{}, fun) do
    session = open(handlers)

    try do
      fun.(session)
    after
      close(session)
    end
  end

  @doc "The session's runtime, started on first use."
  @spec runtime(t()) :: pid()
  def runtime(%__MODULE__{agent: agent}) do
    Agent.get_and_update(agent, fn
      %{runtime: nil} = state ->
        {:ok, runtime} = QuickBEAM.start(handlers: state.handlers)
        {runtime, %{state | runtime: runtime}}

      %{runtime: runtime} = state ->
        {runtime, state}
    end)
  end

  @doc """
  Runs `load` with the runtime the first time `key` is asked for, such as a
  file's macro bundle, and returns its result then and every time after.
  """
  @spec once(t(), term(), (pid() -> result)) :: result when result: term()
  def once(%__MODULE__{agent: agent} = session, key, load) do
    case Agent.get(agent, &Map.fetch(&1.loaded, key)) do
      {:ok, result} ->
        result

      :error ->
        result = load.(runtime(session))
        Agent.update(agent, &put_in(&1, [:loaded, key], result))
        result
    end
  end

  @doc "Stops the runtime, if one started, and the session."
  @spec close(t()) :: :ok
  def close(%__MODULE__{agent: agent}) do
    case Agent.get(agent, & &1.runtime) do
      nil -> :ok
      runtime -> QuickBEAM.stop(runtime)
    end

    Agent.stop(agent)
  end
end
