defmodule Mix.Tasks.Exq.Run do
  use Mix.Task

  @shortdoc "Starts the Exq worker"

  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:exq)
    IO.puts("Started Exq")
    :timer.sleep(:infinity)
  end
end
