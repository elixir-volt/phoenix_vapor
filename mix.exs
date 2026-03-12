defmodule LiveVueNext.MixProject do
  use Mix.Project

  def project do
    [
      app: :live_vue_next,
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
      {:oxc, path: "../oxc_ex", override: true},
      {:quickbeam, path: "../quickbeam", optional: true}
    ]
  end
end
