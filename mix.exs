defmodule Exq.Mixfile do
  use Mix.Project

  def project do
    [ app: :exq,
      version: "0.1.0",
      elixir: "~> 1.0.0",
      elixirc_paths: ["lib", "web"],
      package: [
        contributors: ["Alex Kira", "Justin McNally", "Benjamin Tan Wei Hao"],
        links: %{"GitHub" => "https://github.com/akira/exq"}
      ],
      description: """
      Exq is a job processing library compatible with Resque / Sidekiq for the Elixir language.
      """,
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [
      mod: { Exq, [] },
      applications: [:logger]
    ]
  end

  # Returns the list of dependencies in the format:
  # { :foobar, "0.1", git: "https://github.com/elixir-lang/foobar.git" }
  defp deps do
    [
      { :uuid, "~> 0.1.5", github: 'zyro/elixir-uuid' },
      { :eredis, github: 'wooga/eredis', tag: 'v1.0.5' },
      { :poison, "~> 1.2.0"},
      { :timex, "~> 0.13.0" },
      { :plug, "0.8.1"},
      { :cowboy, "~> 1.0.0" }
    ]
  end
end
