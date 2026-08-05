defmodule SimpleMCP.MixProject do
  use Mix.Project

  def project do
    [
      app: :simple_mcp,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      description: "A minimal, dependency-light MCP server library for Elixir",
      package: package(),
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def cli do
    [preferred_envs: [check: :test, "check.all": :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {SimpleMCP.Application, []}
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.18"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end

  defp aliases do
    [
      check: [
        "format --check-formatted",
        "credo --strict",
        "compile --warnings-as-errors",
        "test"
      ],
      "check.all": [
        "format --check-formatted",
        "credo --strict",
        "compile --warnings-as-errors",
        "test",
        "dialyzer"
      ]
    ]
  end
end
