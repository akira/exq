defmodule Mix.Tasks.Exq.Run do
  use Mix.Task

  @shortdoc "Starts the Exq worker"

  def run(args) do
    IO.puts("Starting Exq...")
    Mix.Task.run "run", ["--no-halt"] ++ args
  end
end
