Code.require_file "test_helper.exs", __DIR__

defmodule FlakyConnectionTest do
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
      send(:tester, :done)
    end
  end

  test "redis_timeout allows for higher latency" do
    Application.start(:ranch)
    conn = FlakyConnection.start(redis_host, redis_port)

    Process.register(self(), :tester)
    {:ok, sup} = Exq.start([name: :perf, host: 'localhost', port: conn.port, namespace: "test", concurrency: :infinite])

    FlakyConnection.set_latency(conn, 1000)

    Mix.Config.persist([exq: [redis_timeout: 2000]])

    {:ok, _} = Exq.enqueue(:perf, "default", FlakyConnectionTest.Worker, ["work"])

    stop_process(sup)
  end

  test "redis_timeout higher than 5000 fails =(" do
    Application.start(:ranch)
    conn = FlakyConnection.start(redis_host, redis_port)

    Process.register(self(), :tester)
    {:ok, sup} = Exq.start([name: :perf, host: 'localhost', port: conn.port, namespace: "test", concurrency: :infinite])

    FlakyConnection.set_latency(conn, 6000)

    Mix.Config.persist([exq: [redis_timeout: 10000, genserver_timeout: 10000]])

    {:ok, _} = Exq.enqueue(:perf, "default", FlakyConnectionTest.Worker, ["work"])

    stop_process(sup)
  end
end
