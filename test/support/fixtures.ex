defmodule PhoenixVapor.Fixtures do
  @moduledoc false

  # Paths to the shared `.vue` fixtures in `test/fixtures`.

  @dir Path.expand("../fixtures", __DIR__)

  @spec path(Path.t()) :: Path.t()
  def path(name), do: Path.join(@dir, name)
end
