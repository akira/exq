defmodule Mix.Tasks.Exq.Run do
  use Mix.Task

  @shortdoc "Starts the Exq worker"

  def run(_args) do
    Exq.start_link()
    IO.puts("Started Exq")
    :timer.sleep(:infinity)
  end
end
