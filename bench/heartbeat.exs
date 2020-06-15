{:ok, _} = Application.ensure_all_started(:redix)

defmodule FastWorker do
  def perform() do
  end
end

defmodule SlowWorker do
  def perform() do
    Process.sleep(60_000)
  end
end

defmodule LoadGenerator do
  def generate(exq) do
    {:ok, _} = Exq.enqueue(Exq, "default", FastWorker, [])
    {:ok, _} = Exq.enqueue(Exq, "default", SlowWorker, [])
    Process.sleep(1000)
    generate(exq)
  end
end

defmodule NodeIdentifier.UUID do
  def node_id do
    Agent.get(:agent, & &1)
  end
end

Application.put_env(:exq, :node_identifier, NodeIdentifier.UUID)
{:ok, _} = Agent.start_link(fn -> "controller" end, name: :agent)

{:ok, controller} =
  Exq.start_link(name: Exq, concurrency: 0, heartbeat_enable: true, heartbeat_interval: 1000)

spawn(fn ->
  LoadGenerator.generate(controller)
end)

workers =
  for _i <- 1..50 do
    id = UUID.uuid4()
    Agent.update(:agent, fn _ -> id end)

    {:ok, worker} =
      Exq.start_link(
        name: String.to_atom(id),
        concurrency: 10,
        heartbeat_enable: true,
        heartbeat_interval: 1000
      )

    worker
  end

Process.sleep(:infinity)
