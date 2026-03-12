defmodule PhoenixVapor.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/elixir-volt/phoenix_vapor"

  def project do
    [
      app: :phoenix_vapor,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "PhoenixVapor",
      description: "Vue templates as native Phoenix LiveView renders — compile Vue syntax to %Rendered{} via Vapor IR.",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Volt" => "https://github.com/elixir-volt/volt"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "PhoenixVapor",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}"
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:vize, "~> 0.5.0 or ~> 0.6.0"},
      {:oxc, "~> 0.5.0"},
      {:quickbeam, "~> 0.3.0", optional: true},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end
end
