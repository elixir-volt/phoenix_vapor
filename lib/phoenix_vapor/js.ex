defmodule PhoenixVapor.JS do
  @moduledoc false
  # A QuickBEAM runtime, or a lighter context on a `QuickBEAM.ContextPool` when
  # a pool is configured.

  @type t :: {:runtime | :context, pid()}

  @spec start(atom() | pid() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  def start(pool, opts \\ [])

  def start(nil, opts) do
    with {:ok, pid} <- QuickBEAM.start(opts), do: {:ok, {:runtime, pid}}
  end

  def start(pool, opts) do
    with {:ok, pid} <- QuickBEAM.Context.start_link([pool: pool] ++ opts),
         do: {:ok, {:context, pid}}
  end

  @spec eval(t(), String.t()) :: {:ok, term()} | {:error, term()}
  def eval({:runtime, pid}, code), do: QuickBEAM.eval(pid, code)
  def eval({:context, pid}, code), do: QuickBEAM.Context.eval(pid, code)

  @spec call(t(), String.t(), list()) :: {:ok, term()} | {:error, term()}
  def call({:runtime, pid}, fun, args), do: QuickBEAM.call(pid, fun, args)
  def call({:context, pid}, fun, args), do: QuickBEAM.Context.call(pid, fun, args)

  @spec stop(t()) :: :ok
  def stop({:runtime, pid}), do: QuickBEAM.stop(pid)
  def stop({:context, pid}), do: QuickBEAM.Context.stop(pid)
end
