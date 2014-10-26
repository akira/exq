defmodule Exq.Mixfile do
  use Mix.Project

  def project do
    [ app: :exq,
      version: "0.0.2",
      elixir: "~> 1.0.0",
      deps: deps ]
  end

  # Configuration for the OTP application
  def application do
    [
      applications: [:logger]
    ]
  end

  # Returns the list of dependencies in the format:
  # { :foobar, "0.1", git: "https://github.com/elixir-lang/foobar.git" }
  defp deps do
    [
      { :eredis, github: 'wooga/eredis', tag: 'v1.0.5' },
      { :jsex, "2.0.0"}
    ]
  end
end
