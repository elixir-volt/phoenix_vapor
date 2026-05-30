defmodule PhoenixVapor.Prop do
  @moduledoc """
  Helpers for assigning advanced hybrid props.
  """

  defmodule Always do
    @moduledoc false
    defstruct [:value]
  end

  defmodule Optional do
    @moduledoc false
    defstruct [:fun]
  end

  defmodule Defer do
    @moduledoc false
    defstruct [:fun, group: "default"]
  end

  @type always :: %Always{value: term()}
  @type optional :: %Optional{fun: function()}
  @type defer :: %Defer{fun: function(), group: String.t()}
  @type preserved_key :: {:preserve, atom() | String.t()}

  @doc """
  Marks a prop as always included when its key is part of the hybrid prop set.
  """
  @spec always(term()) :: always()
  def always(value), do: %Always{value: value}

  @doc """
  Marks a prop as optional.

  Optional props are omitted from full hybrid envelopes. A later deferred/partial
  request mechanism can explicitly resolve them without changing the assignment
  API.
  """
  @spec optional(function()) :: optional()
  def optional(fun) when is_function(fun, 0), do: %Optional{fun: fun}

  def optional(_) do
    raise ArgumentError, "PhoenixVapor.Prop.optional/1 expects a zero-arity function"
  end

  @doc """
  Marks a prop as deferred until the hybrid client requests its group.
  """
  @spec defer(function(), String.t()) :: defer()
  def defer(fun, group \\ "default")

  def defer(fun, group) when is_function(fun, 0) and is_binary(group) do
    %Defer{fun: fun, group: group}
  end

  def defer(_, _) do
    raise ArgumentError,
          "PhoenixVapor.Prop.defer/2 expects a zero-arity function and string group"
  end

  @doc """
  Preserves a prop key exactly for future key transformation features.
  """
  @spec preserve_case(atom() | String.t()) :: preserved_key()
  def preserve_case(key) when is_atom(key) or is_binary(key), do: {:preserve, key}
end
