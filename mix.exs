defmodule PhoenixVapor.MixProject do
  use Mix.Project

  @version "0.3.1"
  @source_url "https://github.com/elixir-volt/phoenix_vapor"

  def project do
    [
      app: :phoenix_vapor,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      name: "PhoenixVapor",
      description:
        "Vue templates as native Phoenix LiveView renders — compile Vue syntax to %Rendered{} via Vapor IR.",
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

  defp aliases do
    [
      "test.unit": ["test test/phoenix_vapor"],
      "test.integration": ["test test/integration"],
      "test.e2e": ["test test/e2e --include e2e"],
      ci: [
        "cmd env MIX_ENV=test mix test.unit",
        "cmd env MIX_ENV=test mix test.integration",
        "cmd env MIX_ENV=test mix test.e2e"
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Volt" => "https://github.com/elixir-volt/volt"
      },
      files: ~w(lib priv/js .formatter.exs mix.exs README.md ARCHITECTURE.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "PhoenixVapor",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "ARCHITECTURE.md",
        "docs/hybrid-architecture.md",
        "docs/comparisons/fronix-wire-protocol.md",
        "docs/comparisons/hologram.md",
        "docs/comparisons/nested-props.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ["docs/hybrid-architecture.md"],
        Comparisons: ~r/docs\/comparisons\/.*/
      ],
      source_ref: "v#{@version}",
      skip_undefined_reference_warnings_on: ["ARCHITECTURE.md"]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.2"},
      {:vize, "~> 0.14.2"},
      {:oxc, "~> 0.17.8"},
      {:quickbeam, "~> 0.10.20", optional: true},
      {:volt, "~> 0.17.10", optional: true, runtime: false},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false}
    ]
  end
end
