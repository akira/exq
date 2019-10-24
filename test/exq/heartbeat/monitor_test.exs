defmodule Exq.Heartbeat.MonitorTest do
  use ExUnit.Case
  import ExqTestUtil
  alias Exq.Support.Config
  alias Exq.Redis.Heartbeat

  @opts [
    redis: :testredis,
    heartbeat_enable: true,
    heartbeat_interval: 200,
    missed_heartbeats_allowed: 3,
    queues: ["default"],
    namespace: "test",
    name: ExqHeartbeat,
    stats: ExqHeartbeat.Stats
  ]

  setup do
    TestRedis.setup()

    on_exit(fn ->
      wait()
      TestRedis.teardown()
    end)
  end

  test "re-enqueues orphaned jobs from backup queue" do
    {:ok, _} = Exq.Stats.Server.start_link(@opts)
    redis = :testredis

    servers =
      for i <- 1..5 do
        {:ok, heartbeat} =
          Exq.Heartbeat.Server.start_link(Keyword.put(@opts, :node_id, to_string(i)))

        {:ok, monitor} =
          Exq.Heartbeat.Monitor.start_link(Keyword.put(@opts, :node_id, to_string(i)))

        %{heartbeat: heartbeat, monitor: monitor}
      end

    assert {:ok, 1} = working(redis, "3")
    Process.sleep(1000)
    assert alive_nodes(redis) == ["1", "2", "3", "4", "5"]
    assert queue_length(redis, "3") == {:ok, 1}
    server = Enum.at(servers, 2)
    :ok = GenServer.stop(server.heartbeat)
    Process.sleep(2000)

    assert alive_nodes(redis) == ["1", "2", "4", "5"]
    assert queue_length(redis, "3") == {:ok, 0}
  end

  test "shouldn't dequeue from live node" do
    redis = :testredis
    namespace = Config.get(:namespace)
    interval = 100
    missed_heartbeats_allowed = 3
    Heartbeat.register(redis, namespace, "1")
    assert {:ok, 1} = working(redis, "1")
    Process.sleep(1000)

    {:ok, %{"1" => score}} =
      Heartbeat.orphaned_nodes(
        redis,
        namespace,
        interval,
        missed_heartbeats_allowed
      )

    assert queue_length(redis, "1") == {:ok, 1}
    Heartbeat.re_enqueue_backup(redis, namespace, "1", "default", score)
    assert queue_length(redis, "1") == {:ok, 0}

    Heartbeat.register(redis, namespace, "1")
    assert {:ok, 1} = working(redis, "1")
    Process.sleep(1000)

    {:ok, %{"1" => score}} =
      Heartbeat.orphaned_nodes(
        redis,
        namespace,
        interval,
        missed_heartbeats_allowed
      )

    # The node came back after we got the orphan list, but before we could re-enqueue
    Heartbeat.register(redis, namespace, "1")
    Heartbeat.re_enqueue_backup(redis, namespace, "1", "default", score)
    assert queue_length(redis, "1") == {:ok, 1}

    Process.sleep(1000)

    {:ok, %{"1" => score}} =
      Heartbeat.orphaned_nodes(
        redis,
        namespace,
        interval,
        missed_heartbeats_allowed
      )

    # The node got removed by another heartbeat monitor
    Heartbeat.unregister(redis, namespace, "1")
    Heartbeat.re_enqueue_backup(redis, namespace, "1", "default", score)
    assert queue_length(redis, "1") == {:ok, 1}
  end

  defp alive_nodes(redis) do
    {:ok, nodes} =
      Redix.command(redis, ["ZRANGEBYSCORE", "#{Config.get(:namespace)}:heartbeats", "0", "+inf"])

    Enum.sort(nodes)
  end

  defp working(redis, node_id) do
    Redix.command(redis, [
      "LPUSH",
      Exq.Redis.JobQueue.backup_queue_key(Config.get(:namespace), node_id, "default"),
      "{}"
    ])
  end

  defp queue_length(redis, node_id) do
    Redix.command(redis, [
      "LLEN",
      Exq.Redis.JobQueue.backup_queue_key(Config.get(:namespace), node_id, "default")
    ])
  end
end
