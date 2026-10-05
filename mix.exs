defmodule PhoenixVapor.MixProject do
  use Mix.Project

  @version "0.6.0"
  @source_url "https://github.com/elixir-volt/phoenix_vapor"

  def project do
    [
      app: :phoenix_vapor,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "PhoenixVapor",
      description: "Vue templates and single-file components for Phoenix LiveView",
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      dialyzer: [plt_add_apps: [:mix, :volt]]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def cli, do: [preferred_envs: [ci: :test, lint: :test]]

  def application do
    [extra_applications: [:logger]]
  end

  defp aliases do
    [
      setup: ["deps.get", "volt.priv.vendor priv/ts", "npm.install"],
      "test.unit": ["test test/phoenix_vapor"],
      "test.integration": ["test test/integration"],
      "test.e2e": ["test test/e2e --include e2e"],
      lint: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "ex_dna",
        "reach.check --dead-code --smells --strict --baseline .reach-baseline.json",
        "dialyzer",
        "docs --warnings-as-errors",
        "volt.js.check --type-aware --type-check"
      ],
      # tsgolint and the e2e tests' Vue come from node_modules; the e2e tests
      # also need the Reka bundle.
      ci: ["npm.install", "lint", "phoenix_vapor.bundle --name reka-dialog", "test --include e2e"],
      # A separate process, so compiling for vendoring leaves Hex's own tasks loaded.
      "hex.build": ["cmd mix volt.priv.vendor priv/ts", "hex.build"],
      "hex.publish": ["cmd mix volt.priv.vendor priv/ts", "hex.publish"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Volt" => "https://github.com/elixir-volt/volt"
      },
      files:
        ~w(lib priv/ts package.json .formatter.exs mix.exs README.md ARCHITECTURE.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/introduction/getting-started.md",
        "guides/features/templates.md",
        "guides/features/reactive.md",
        "guides/features/hybrid.md",
        "guides/features/full-runtime.md",
        "guides/cheatsheets/modes.cheatmd",
        "ARCHITECTURE.md",
        "docs/hybrid-architecture.md",
        "docs/comparisons/fronix-wire-protocol.md",
        "docs/comparisons/hologram.md",
        "docs/comparisons/nested-props.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Introduction: ~r/guides\/introduction\//,
        Features: ~r/guides\/features\//,
        Cheatsheets: ~r/guides\/cheatsheets\//,
        Internals: ["ARCHITECTURE.md", "docs/hybrid-architecture.md"],
        Comparisons: ~r/docs\/comparisons\//
      ],
      # Both name internal modules on purpose: where they live, and what moved.
      skip_undefined_reference_warnings_on: ["ARCHITECTURE.md", "CHANGELOG.md"]
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.2"},
      {:vize, "~> 0.17.0"},
      {:oxc, "~> 0.18.1"},
      {:jason, "~> 1.4"},
      {:quickbeam, "~> 0.11.2"},
      {:volt, "~> 0.21.0", runtime: false},
      {:ex_doc, "~> 0.40.3", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.0", only: [:dev, :test], runtime: false}
    ]
  end
end
