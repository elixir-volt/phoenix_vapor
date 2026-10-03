defmodule PhoenixVapor.ExpressionError do
  @moduledoc """
  Raised when a template expression can't be evaluated, such as a call to a
  function that isn't defined, with where the expression is in its file.
  """

  defexception [:expression, :reason, :file, :position]

  @type t :: %__MODULE__{
          expression: String.t(),
          reason: String.t(),
          file: Path.t() | nil,
          position: PhoenixVapor.Template.position() | nil
        }

  @impl true
  def message(%__MODULE__{} = error) do
    location(error) <> "can't evaluate `#{error.expression}`: #{error.reason}"
  end

  defp location(%{file: nil, position: nil}), do: ""
  defp location(%{file: file, position: nil}), do: Path.relative_to_cwd(file) <> ": "
  defp location(%{file: nil, position: {line, column}}), do: "#{line}:#{column}: "

  defp location(%{file: file, position: {line, column}}),
    do: "#{Path.relative_to_cwd(file)}:#{line}:#{column}: "
end
