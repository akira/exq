defmodule MemoryTest do
  use ExUnit.Case
  require Logger
  import ExqTestUtil

  setup do
    TestRedis.setup
    on_exit fn ->
      TestRedis.teardown
    end
    :ok
  end

  defmodule Worker do
    def perform(arg) do
      if arg == "last" do
        Logger.info("Last message detected")
        send(:tester, :done)
      end
    end
  end

  @tag timeout: :infinity
  test "test memory bloat" do
    starting_memory = :erlang.memory(:total)

    Process.register(self(), :tester)

    {:ok, sup} = Exq.start_link(scheduler_enable: true)
    for _ <- 1..10_000, do: Exq.enqueue_in(Exq, "default", 5, MemoryTest.Worker, [Enum.reduce(1..10_000, "", fn _, acc -> acc <> "." end)])
    Exq.enqueue_in(Exq, "default", 5, MemoryTest.Worker, ["last"])

    # Wait for last message
    receive do
      :done -> Logger.info("Received done")
    end

    :timer.sleep(1000)

    memory_used  = :erlang.memory(:total) - starting_memory
    Logger.debug "Memory used #{memory_used / (1_024 * 1024)} mb"
    count = Exq.Redis.Connection.zcard!(:testredis, "test:schedule")

    assert count == 0
    assert memory_used < 10 * (1_024 * 1_024) # 10mb
    # let stats finish
    stop_process(sup)
  end
end
