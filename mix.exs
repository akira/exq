defmodule Exq.Mixfile do
  use Mix.Project

  @source_url "https://github.com/akira/exq"
  @version "0.19.0"

  def project do
    [
      app: :exq,
      version: @version,
      elixir: "~> 1.7",
      elixirc_paths: ["lib"],
      test_coverage: [tool: ExCoveralls],
      deps: deps(),
      docs: docs(),
      package: package(),
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [
      mod: {Exq, []},
      applications: [:logger, :redix, :elixir_uuid]
    ]
  end

  defp deps do
    [
      {:elixir_uuid, ">= 1.2.0"},
      {:redix, ">= 0.9.0"},
      {:poison, ">= 1.2.0 and < 6.0.0", optional: true},
      {:jason, "~> 1.0", optional: true},
      {:excoveralls, "~> 0.18", only: :test},
      {:castore, "~> 1.0", only: :test},
      {:flaky_connection,
       git: "https://github.com/ananthakumaran/flaky_connection.git", only: :test},

      # docs
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:benchee, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      description: """
      Exq is a job processing library compatible with Resque / Sidekiq for the
      Elixir language.
      """,
      maintainers: ["Alex Kira", "zhongwencool", "Anantha Kumaran"],
      licenses: ["Apache-2.0"],
      files: ~w(lib test) ++ ~w(LICENSE mix.exs CHANGELOG.md README.md),
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      extras: ["CHANGELOG.md", "README.md"],
      main: "readme",
      formatters: ["html"],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end
end
