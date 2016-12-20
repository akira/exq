defmodule PerformanceTest do
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

  test "test to_job_serialized performance" do
    started = :os.timestamp
    max_timeout_ms = 1_000
    for _ <- 1..1000, do: Exq.Redis.JobQueue.to_job_serialized("default", PerformanceTest.Worker, ["keep_on_trucking"], 10)
    elapsed_ms = :timer.now_diff(:os.timestamp, started) / 1_000
    Logger.debug "to_job_serialized performance test took #{elapsed_ms / 1_000} secs"
    assert elapsed_ms < max_timeout_ms
  end

  test "performance is in acceptable range" do

    Process.register(self(), :tester)
    started = :os.timestamp
    max_timeout_ms = 5 * 1_000

    {:ok, sup} = Exq.start_link
    for _ <- 1..1000, do: Exq.enqueue(Exq, "default", PerformanceTest.Worker, ["keep_on_trucking"])
    Exq.enqueue(Exq, "default", PerformanceTest.Worker, ["last"])

    # Wait for last message
    receive do
      :done -> Logger.info("Received done")
    after
      # This won't count enqueue
      max_timeout_ms  -> assert false, "Timeout of #{max_timeout_ms} reached for performance test"
    end

    elapsed_ms = :timer.now_diff(:os.timestamp, started) / 1_000
    Logger.debug "Perf test took #{elapsed_ms / 1_000} secs"
    count = Exq.Redis.Connection.llen!(:testredis, "test:queue:default")

    assert count == 0
    assert elapsed_ms < max_timeout_ms
    # let stats finish
    wait_long
    stop_process(sup)
  end

end
