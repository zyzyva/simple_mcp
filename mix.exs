defmodule SimpleMCP.MixProject do
  use Mix.Project

  def project do
    [
      app: :simple_mcp,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A minimal, dependency-light MCP server library for Elixir",
      package: package()
    ]
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
      {:plug, "~> 1.18"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{}
    ]
  end
end
