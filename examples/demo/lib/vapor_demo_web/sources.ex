defmodule VaporDemoWeb.Sources do
  @moduledoc """
  The demo's own components and pages, read while compiling, so the x-ray can
  show the source of a region. Only these files are served, by the path
  relative to the project.
  """

  @behaviour Plug

  @root Path.expand("../..", __DIR__)

  @files (for pattern <- ["lib/vapor_demo_web/**/*.{vue,ex}", "assets/js/ui/*.vue"],
              path <- Path.wildcard(Path.join(@root, pattern)),
              into: %{} do
            @external_resource path
            {Path.relative_to(path, @root), File.read!(path)}
          end)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%{path_params: %{"path" => parts}} = conn, _opts) do
    case Map.fetch(@files, Path.join(parts)) do
      {:ok, source} ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, source)

      :error ->
        Plug.Conn.send_resp(conn, 404, "")
    end
  end
end
