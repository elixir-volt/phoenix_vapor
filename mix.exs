defmodule PhoenixVapor.MixProject do
  use Mix.Project

  @version "0.3.3"
  @source_url "https://github.com/elixir-volt/phoenix_vapor"

  def project do
    [
      app: :phoenix_vapor,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "PhoenixVapor",
      description:
        "Vue templates as native Phoenix LiveView renders — compile Vue syntax to %Rendered{} via Vapor IR.",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix, :volt]]
    ]
  end

  def cli, do: [preferred_envs: [ci: :test, lint: :test]]

  def application do
    [extra_applications: [:logger]]
  end

  defp aliases do
    [
      "test.unit": ["test test/phoenix_vapor"],
      "test.integration": ["test test/integration"],
      "test.e2e": ["test test/e2e --include e2e"],
      lint: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "ex_dna",
        "reach.check --dead-code --smells --strict --baseline .reach-baseline.json",
        "dialyzer"
      ],
      # The e2e tests need Vue from node_modules and the Reka bundle.
      ci: ["lint", "npm.install", "phoenix_vapor.bundle --name reka-dialog", "test --include e2e"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Volt" => "https://github.com/elixir-volt/volt"
      },
      files: ~w(lib priv/js/hybrid-bridge.js priv/js/runtime-setup.js priv/js/vue-reactivity.js
                 .formatter.exs mix.exs README.md ARCHITECTURE.md CHANGELOG.md LICENSE)
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
      {:vize, "~> 0.15.0"},
      {:oxc, "~> 0.18.1"},
      {:quickbeam, "~> 0.11.2", optional: true},
      {:volt, "~> 0.19.0", optional: true, runtime: false},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.0", only: [:dev, :test], runtime: false}
    ]
  end
end
