defmodule PhoenixVapor.MixProject do
  use Mix.Project

  @version "0.2.1"
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
      files: ~w(lib priv/js .formatter.exs mix.exs README.md ARCHITECTURE.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "PhoenixVapor",
      extras: ["README.md", "ARCHITECTURE.md", "LICENSE"],
      source_ref: "v#{@version}",
      skip_undefined_reference_warnings_on: ["ARCHITECTURE.md"]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.1"},
      {:vize, "~> 0.10.0"},
      {:oxc, "~> 0.11.0"},
      {:quickbeam, "~> 0.10.8", optional: true},
      {:volt, "~> 0.10.1", optional: true, runtime: false},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end
end
