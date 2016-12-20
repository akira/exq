defmodule JobStatTest do
  use ExUnit.Case

  alias Exq.Redis.JobStat
  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue

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

  setup do
    TestRedis.setup
    on_exit(fn -> TestRedis.teardown end)
    Exq.start_link

    :ok
  end

  test "show realtime statistics" do
    {:ok, time1} = DateTime.from_unix(1452173400, :seconds)
    {:ok, time2} = DateTime.from_unix(1452175515, :seconds)

    JobStat.record_processed(:testredis, "test", nil, time1)
    JobStat.record_processed(:testredis, "test", nil, time2)
    JobStat.record_processed(:testredis, "test", nil, time1)
    JobStat.record_failure(:testredis, "test", nil, nil, time1)
    JobStat.record_failure(:testredis, "test", nil, nil, time2)

    Exq.start_link(mode: :api, name: ExqApi)
    {:ok, failures, successes} = Exq.Api.realtime_stats(ExqApi.Api)

    assert List.keysort(failures, 0) == [{"2016-01-07 13:30:00Z", "1"}, {"2016-01-07 14:05:15Z", "1"}]
    assert List.keysort(successes, 0) == [{"2016-01-07 13:30:00Z", "2"}, {"2016-01-07 14:05:15Z", "1"}]
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

  test "clear failed" do
    Enum.each [1,2,3], fn(_) -> enqueue_and_fail_job(:testredis) end
    assert dead_jobs_count(:testredis) == 3

    JobStat.clear_failed(:testredis, "test")
    assert dead_jobs_count(:testredis) == 0
    assert Connection.get!(:testredis, "test:stat:failed") == "0"
  end
end
