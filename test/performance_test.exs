Code.require_file "test_helper.exs", __DIR__

defmodule PerformanceTest do
  use ExUnit.Case
  require Logger
  setup do
    TestRedis.setup
    on_exit fn ->
      TestRedis.teardown
    end
    :ok
  end


  def perform(a1, a2) do

  end


  test "performance is in acceptable range" do
    started = :os.timestamp
    {:ok, pid} = Exq.start([host: '127.0.0.1', port: 6379, namespace: "test"])
    for n <- 1..4000, do: Exq.enqueue(pid, "default", "PerformanceTest", ["arg1", "arg2"])
    {:ok, timer} = :timer.exit_after(1, pid, :normal)
    elapsed = :timer.now_diff(:os.timestamp, started)
    count = Exq.Redis.llen!(:testredis, "test:queue:default")
    assert count == "0"
    assert elapsed < 5000000
    Logger.debug "Perf test took #{elapsed}"
  end

end