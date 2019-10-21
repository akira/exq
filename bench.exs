defmodule BenchmarkWorker do
  def perform() do
  end
end

{:ok, _} = Application.ensure_all_started(:exq)
Logger.configure(level: :warn)

Benchee.run(
  %{
    "enqueue" => fn -> {:ok, _} = Exq.enqueue(Exq, "default", BenchmarkWorker, []) end
  },
  parallel: 100
)
