defmodule VaporDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :vapor_demo,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {VaporDemo.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [ci: :test, lint: :test, precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.2.9"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_test, "~> 0.5", only: :test, runtime: false},
      {:phoenix_test_playwright, "~> 0.14", only: :test, runtime: false},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, ">= 1.12.5 and < 2.0.0"},
      {:phoenix_vapor, path: "../.."},
      {:quickbeam, "~> 0.11.2"},
      {:volt, "~> 0.21.0"},
      {:phoenix_replay, "~> 0.6.2"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: [
        "deps.get",
        "npm.install",
        "phoenix_vapor.bundle --entry assets/js/bundles/reka-dialog.js",
        "assets.build"
      ],
      "assets.build": ["volt.build --tailwind"],
      "assets.deploy": ["volt.build --tailwind", "phx.digest"],
      # What CI runs, after installing Playwright's browser.
      ci: [
        "npm.install --frozen",
        "phoenix_vapor.bundle --entry assets/js/bundles/reka-dialog.js",
        "assets.build",
        "lint",
        "test"
      ],
      lint: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "volt.js.check --type-aware --type-check"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
