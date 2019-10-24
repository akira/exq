defmodule Exq.Heartbeat.WatcherTest do
  use ExUnit.Case
  import ExqTestUtil
  alias Exq.Support.Config

  setup do
    TestRedis.setup()

    on_exit(fn ->
      wait()
      TestRedis.teardown()
    end)
  end

  test "re-enqueues orphaned jobs from backup queue" do
    redis = :testredis

    config = [
      redis: redis,
      heartbeat_enable: true,
      heartbeat_interval: 500,
      missed_heartbeats_allowed: 3,
      queues: ["default"],
      namespace: Config.get(:namespace)
    ]

    servers =
      for i <- 1..5 do
        {:ok, heartbeat} =
          Exq.Heartbeat.Server.start_link(Keyword.put(config, :node_id, to_string(i)))

        {:ok, watcher} =
          Exq.Heartbeat.Watcher.start_link(Keyword.put(config, :node_id, to_string(i)))

        %{heartbeat: heartbeat, watcher: watcher}
      end

    assert {:ok, 1} = working(redis, "3")
    Process.sleep(2000)
    assert alive_nodes(redis) == ["1", "2", "3", "4", "5"]
    assert queue_length(redis, "3") == {:ok, 1}
    server = Enum.at(servers, 2)
    :ok = GenServer.stop(server.heartbeat)
    Process.sleep(4000)

    assert alive_nodes(redis) == ["1", "2", "4", "5"]
    assert queue_length(redis, "3") == {:ok, 0}
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
