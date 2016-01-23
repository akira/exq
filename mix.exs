defmodule Exq.Mixfile do
  use Mix.Project

  def project do
    [ app: :exq,
      version: "0.6.3",
      elixir: "~> 1.0.0 or ~> 1.1.1 or ~> 1.2",
      elixirc_paths: ["lib"],
      package: [
        maintainers: ["Alex Kira", "Justin McNally", "Nick Sanders", "Udo Kramer", "Daniel Perez", "David Le", "akki91", "Roman Smirnov", "Mike Lawlor", "Benjamin Tan Wei Hao", "Rob Gilson"],
        links: %{"GitHub" => "https://github.com/akira/exq"},
        files: ~w(lib test) ++
               ~w(LICENSE mix.exs README.md)
      ],
      description: """
      Exq is a job processing library compatible with Resque / Sidekiq for the Elixir language.
      """,
      deps: deps,
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Configuration for the OTP application
  def application do
    [
      mod: { Exq, [] },
      applications: [:logger, :tzdata, :redix, :timex, :uuid]
    ]
  end

  # Returns the list of dependencies in the format:
  # { :foobar, "0.1", git: "https://github.com/elixir-lang/foobar.git" }
  defp deps do
    [
      { :uuid, ">= 1.0.0" },
      { :redix, ">= 0.3.4"},
      { :poison, ">= 1.2.0 and < 2.0.0"},
      { :timex, ">= 1.0.0" },
      { :excoveralls, "~> 0.3", only: :test },
      { :flaky_connection, git: "https://github.com/hamiltop/flaky_connection.git", only: :test}
    ]
  end
end
