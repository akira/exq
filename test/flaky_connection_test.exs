defmodule FlakyConnectionTest do
  use ExUnit.Case
  require Logger
  import ExqTestUtil

  @moduletag :failure_scenarios

  setup do
    TestRedis.setup()

    :ok
  end

  defmodule Worker do
    def perform(_) do
      send(:tester, :done)
    end
  end

  test "redis_timeout allows for higher latency" do
    Application.start(:ranch)
    conn = FlakyConnection.start(redis_host(), redis_port())

    # Needs to be x2 latency + ~10
    Mix.Config.persist(exq: [redis_timeout: 2010])

    Process.register(self(), :tester)
    {:ok, sup} = Exq.start_link(name: ExqPerf, port: conn.port)

    FlakyConnection.set_latency(conn, 1000)

    {:ok, _} = Exq.enqueue(ExqPerf.Enqueuer, "default", FlakyConnectionTest.Worker, ["work"])

    stop_process(sup)
  end

  test "redis_timeout higher than 5000 without genserver_timeout" do
    Application.start(:ranch)
    conn = FlakyConnection.start(redis_host(), redis_port())

    # Needs to be x2 latency + ~10
    Mix.Config.persist(exq: [redis_timeout: 11010])

    Process.register(self(), :tester)

    {:ok, sup} = Exq.start_link(port: conn.port)

    FlakyConnection.set_latency(conn, 5500)

    result =
      try do
        {:ok, _} = Exq.enqueue(Exq.Enqueuer, "default", FlakyConnectionTest.Worker, ["work"])
      catch
        :exit, {:timeout, _} -> :failed
      end

    assert result == :failed

    stop_process(sup)
  end

  test "redis_timeout higher than 5000 with genserver_timeout" do
    Application.start(:ranch)
    conn = FlakyConnection.start(redis_host(), redis_port())

    # redis_timeout needs to be x2 latency + ~10
    # genserver_timeout needs to be x2 latency + ~30
    Mix.Config.persist(exq: [redis_timeout: 11010, genserver_timeout: 11030])

    Process.register(self(), :tester)

    {:ok, sup} = Exq.start_link(port: conn.port)

    FlakyConnection.set_latency(conn, 5500)

    {:ok, _} = Exq.enqueue(Exq.Enqueuer, "default", FlakyConnectionTest.Worker, ["work"])

    stop_process(sup)
  end
end
