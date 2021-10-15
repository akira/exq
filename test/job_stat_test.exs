defmodule JobStatTest do
  use ExUnit.Case

  alias Exq.Redis.JobStat
  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue
  alias Exq.Support.Process
  alias Exq.Support.Job
  alias Exq.Support.Time
  alias Exq.Support.Node

  defmodule EmptyMethodWorker do
    def perform do
      {:ok, "test"}
    end
  end

  def dead_jobs_count(redis) do
    {:ok, count} = Connection.q(redis, ["ZCOUNT", "test:dead", "-inf", "+inf"])
    count
  end

  def enqueue_and_fail_job(redis) do
    Connection.incr!(redis, "test:stat:failed")
    {:ok, jid} = Exq.enqueue(Exq, "queue", EmptyMethodWorker, [])
    {:ok, _job} = JobQueue.find_job(redis, "test", jid, "queue")
    JobQueue.fail_job(redis, "test", %Exq.Support.Job{jid: jid}, "forced error")

    {:ok, jid}
  end

  def create_process_info(host) do
    process_info = %Process{
      pid: inspect(self()),
      host: host,
      payload: %Job{},
      run_at: Time.unix_seconds()
    }

    serialized = Exq.Support.Process.encode(process_info)
    {process_info, serialized}
  end

  setup do
    TestRedis.setup()
    on_exit(fn -> TestRedis.teardown() end)
    Exq.start_link()

    :ok
  end

  test "show realtime statistics" do
    {:ok, time1} = DateTime.from_unix(1_452_173_400_000, :millisecond)
    {:ok, time2} = DateTime.from_unix(1_452_175_515_000, :millisecond)

    JobStat.record_processed(:testredis, "test", nil, time1)
    JobStat.record_processed(:testredis, "test", nil, time2)
    JobStat.record_processed(:testredis, "test", nil, time1)
    JobStat.record_failure(:testredis, "test", nil, nil, time1)
    JobStat.record_failure(:testredis, "test", nil, nil, time2)

    Exq.start_link(mode: :api, name: ExqApi)
    {:ok, failures, successes} = Exq.Api.realtime_stats(ExqApi.Api)

    assert List.keysort(failures, 0) == [
             {"2016-01-07 13:30:00Z", "1"},
             {"2016-01-07 14:05:15Z", "1"}
           ]

    assert List.keysort(successes, 0) == [
             {"2016-01-07 13:30:00Z", "2"},
             {"2016-01-07 14:05:15Z", "1"}
           ]
  end

  test "show realtime statistics with no data" do
    Exq.start_link(mode: :api, name: ExqApi)

    {:ok, failures, successes} = Exq.Api.realtime_stats(ExqApi.Api)

    assert List.keysort(failures, 0) == []
    assert List.keysort(successes, 0) == []
  end

  test "remove queue" do
    Exq.enqueue(Exq, "test_queue", EmptyMethodWorker, [])
    assert Connection.smembers!(:testredis, "test:queues") == ["test_queue"]
    assert Connection.llen!(:testredis, "test:queue:test_queue") == 1

    JobStat.remove_queue(:testredis, "test", "test_queue")
    assert Connection.smembers!(:testredis, "test:queues") == []
    assert Connection.llen!(:testredis, "test:queue:test_queue") == 0
  end

  test "remove failed" do
    {:ok, jid} = enqueue_and_fail_job(:testredis)
    assert dead_jobs_count(:testredis) == 1

    JobStat.remove_failed(:testredis, "test", jid)
    assert dead_jobs_count(:testredis) == 0
    assert Connection.get!(:testredis, "test:stat:failed") == "0"
  end

  test "prune dead nodes" do
    namespace = "test"
    JobStat.node_ping(:testredis, namespace, %Node{identity: "host123", busy: 1})
    JobStat.node_ping(:testredis, namespace, %Node{identity: "host456", busy: 1})

    {process_info, serialized} = create_process_info("host456")
    JobStat.add_process(:testredis, namespace, process_info, serialized)
    assert Enum.count(Exq.Redis.JobStat.processes(:testredis, namespace)) == 1

    JobStat.prune_dead_nodes(:testredis, namespace)
    assert ["host123", "host456"] == JobStat.node_ids(:testredis, namespace) |> Enum.sort()
    Connection.del!(:testredis, "test:host456")
    assert ["host123", "host456"] == JobStat.node_ids(:testredis, namespace) |> Enum.sort()
    JobStat.prune_dead_nodes(:testredis, namespace)
    assert ["host123"] == JobStat.node_ids(:testredis, namespace)
    assert Enum.count(Exq.Redis.JobStat.processes(:testredis, namespace)) == 0
  end

  test "clear failed" do
    Enum.each([1, 2, 3], fn _ -> enqueue_and_fail_job(:testredis) end)
    assert dead_jobs_count(:testredis) == 3

    JobStat.clear_failed(:testredis, "test")
    assert dead_jobs_count(:testredis) == 0
    assert Connection.get!(:testredis, "test:stat:failed") == "0"
  end

  test "add and remove process" do
    namespace = "test"
    JobStat.node_ping(:testredis, "test", %Node{identity: "host123", busy: 1})
    {process_info, serialized} = create_process_info("host123")
    JobStat.add_process(:testredis, namespace, process_info, serialized)
    assert Enum.count(Exq.Redis.JobStat.processes(:testredis, namespace)) == 1

    JobStat.remove_process(:testredis, namespace, process_info)
    assert Enum.count(Exq.Redis.JobStat.processes(:testredis, namespace)) == 0
  end

  test "remove processes on boot" do
    namespace = "test"

    JobStat.node_ping(:testredis, "test", %Node{identity: "host123", busy: 1})
    JobStat.node_ping(:testredis, "test", %Node{identity: "host456", busy: 1})

    # add processes for multiple hosts
    {local_process, serialized1} = create_process_info("host123")
    JobStat.add_process(:testredis, namespace, local_process, serialized1)

    {remote_process, serialized2} = create_process_info("host456")
    JobStat.add_process(:testredis, namespace, remote_process, serialized2)

    assert Enum.count(Exq.Redis.JobStat.processes(:testredis, namespace)) == 2

    # Should cleanup only the host that is passed in
    JobStat.cleanup_processes(:testredis, namespace, "host123")
    processes = Exq.Redis.JobStat.processes(:testredis, namespace)
    assert Enum.count(processes) == 1
    assert Enum.find(processes, fn process -> process.host == "host456" end) != nil
  end
end
