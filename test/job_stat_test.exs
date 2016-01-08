Code.require_file "test_helper.exs", __DIR__

defmodule JobStatTest do
  use ExUnit.Case
  import ExqTestUtil
  use Timex

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
    {:ok, job, _} = JobQueue.find_job(redis, "test", jid, "queue")
    JobQueue.fail_job(redis, "test", %Exq.Support.Job{jid: jid}, "forced error")

    {:ok, jid}
  end

  setup do
    TestRedis.setup
    on_exit(fn -> TestRedis.teardown end)
    Tzdata.EtsHolder.start_link

    :ok
  end

  test "show realtime statistics" do
    Exq.start_link
    state = :sys.get_state(Exq)

    {:ok, time1} = DateFormat.parse("2016-01-07T13:30:00+00", "{ISO}")
    {:ok, time2} = DateFormat.parse("2016-01-07T14:05:15+00", "{ISO}")

    JobStat.record_processed(state.redis, "test", nil, time1)
    JobStat.record_processed(state.redis, "test", nil, time2)
    JobStat.record_processed(state.redis, "test", nil, time1)
    JobStat.record_failure(state.redis, "test", nil, nil, time1)
    JobStat.record_failure(state.redis, "test", nil, nil, time2)

    Exq.Enqueuer.Server.start_link(name: ExqE)
    {:ok, failures, successes} = Exq.Api.realtime_stats(ExqE)

    assert  List.keysort(failures, 0) == [{"2016-01-07 13:30:00 +0000", "1"}, {"2016-01-07 14:05:15 +0000", "1"}]
    assert List.keysort(successes, 0) == [{"2016-01-07 13:30:00 +0000", "2"}, {"2016-01-07 14:05:15 +0000", "1"}]
  end

  test "remove queue" do
    Exq.start_link
    state = :sys.get_state(Exq)

    Exq.enqueue(Exq, "test_queue", EmptyMethodWorker, [])
    assert Connection.smembers!(state.redis, "test:queues") == ["test_queue"]
    assert Connection.llen!(state.redis, "test:queue:test_queue") == 1

    JobStat.remove_queue(state.redis, "test", "test_queue")
    assert Connection.smembers!(state.redis, "test:queues") == []
    assert Connection.llen!(state.redis, "test:queue:test_queue") == 0
  end

  test "remove failed" do
    Exq.start_link
    state = :sys.get_state(Exq)

    {:ok, jid} = enqueue_and_fail_job(state.redis)
    assert dead_jobs_count(state.redis) == 1

    JobStat.remove_failed(state.redis, "test", jid)
    assert dead_jobs_count(state.redis) == 0
    assert Connection.get!(state.redis, "test:stat:failed") == "0"
  end

  test "clear failed" do
    Exq.start_link
    state = :sys.get_state(Exq)

    Enum.each [1,2,3], fn(_) -> enqueue_and_fail_job(state.redis) end
    assert dead_jobs_count(state.redis) == 3

    JobStat.clear_failed(state.redis, "test")
    assert dead_jobs_count(state.redis) == 0
    assert Connection.get!(state.redis, "test:stat:failed") == "0"
  end
end
