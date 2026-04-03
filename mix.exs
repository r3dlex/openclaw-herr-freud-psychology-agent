defmodule HerrFreud.MixProject do
  use Mix.Project

  def project do
    [
      app: :herr_freud,
      version: "1.0.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {HerrFreud.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.22"},
      {:websockex, "~> 0.5"},
      {:quantum, "~> 3.5"},
      {:jason, "~> 1.4"},
      {:hackney, "~> 1.18"},
      {:fs, "~> 11.4"},
      {:mime, "~> 2.0"},
      {:yaml_elixir, "~> 2.9"},
      {:req, "~> 0.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:bypass, "~> 2.1", only: :test},
      {:stream_data, "~> 1.0", only: :test},
      {:meck, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["test"],
      coverage: ["coveralls.html"],
      dialyzer: ["dialyzer --ignore-exit-status 2"]
    ]
  end

  def release do
    [
      herring: [
        steps: [:assemble, :emit_rel_tarball],
        strip_beam: true
      ]
    ]
  end
end
