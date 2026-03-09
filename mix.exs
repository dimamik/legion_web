defmodule LegionWeb.MixProject do
  use Mix.Project

  @source_url "https://github.com/dimamik/legion_web"
  @version "0.1.0"

  def project do
    [
      app: :legion_web,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      listeners: [Phoenix.CodeReloader],
      package: package(),
      name: "LegionWeb",
      description: "Dashboard for the Legion AI agent framework"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {LegionWeb.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp package do
    [
      maintainers: ["Dima Mikielewicz"],
      licenses: ["MIT"],
      files: ~w(lib priv/static* .formatter.exs mix.exs README* LICENSE*),
      links: %{
        GitHub: @source_url
      }
    ]
  end

  defp deps do
    [
      {:legion, path: "../legion"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:makeup, "~> 1.0"},
      {:makeup_elixir, "~> 1.0"},

      # Dev
      {:bandit, "~> 1.5", only: :dev},
      {:esbuild, "~> 0.7", only: :dev, runtime: false},
      {:tailwind, "~> 0.4", only: :dev, runtime: false},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},

      # Test
      {:floki, "~> 0.33", only: :test}
    ]
  end

  defp aliases do
    [
      "assets.build": ["tailwind legion_web", "esbuild legion_web"],
      dev: "run --no-halt dev.exs"
    ]
  end
end
