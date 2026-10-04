defmodule PhoenixVapor.Fixtures do
  @moduledoc false

  # Paths to the shared `.vue` fixtures in `test/fixtures`.

  @dir Path.expand("test/fixtures")

  @spec path(Path.t()) :: Path.t()
  def path(name), do: Path.join(@dir, name)
end
