Code.require_file "test_helper.exs", __DIR__

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

  test "performance is in acceptable range" do

    Process.register(self(), :tester)
    started = :os.timestamp
    max_timeout_ms = 5 * 1_000

    {:ok, sup} = Exq.start([name: :perf, host: '127.0.0.1', port: 6555, namespace: "test"])
    for n <- 1..5000, do: Exq.enqueue(:perf, "default", "PerformanceTest.Worker", ["keep_on_trucking"])
    Exq.enqueue(:perf, "default", "PerformanceTest.Worker", ["last"])

    # Wait for last message
    receive do
      :done -> Logger.info("Received done")
    after
      # This won't count enqueue
      max_timeout_ms  -> assert false, "Timeout of #{max_timeout_ms} reached for performance test"
    end

    elapsed_ms = :timer.now_diff(:os.timestamp, started) / 1_000
    Logger.debug "Perf test took #{elapsed_ms / 1_000} ms"
    count = Exq.Redis.llen!(:testredis, "test:queue:default")

    assert count == "0"
    assert elapsed_ms < max_timeout_ms
    stop_process(sup)
  end

end