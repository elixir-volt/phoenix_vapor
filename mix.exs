defmodule PhoenixVapor.MixProject do
  use Mix.Project

  def project do
    [
      app: :phoenix_vapor,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:vize, path: "../vize_ex"},
      {:oxc, "~> 0.5.0"},
      {:quickbeam, path: "../quickbeam", optional: true},
      {:rustler, ">= 0.0.0", optional: true}
    ]
  end
end
