defmodule JobQueueTest do
  use ExUnit.Case
  alias Exq.Redis.JobQueue
  alias Exq.Support.Job
  alias Exq.Support.Time

  @host 'host-name'

  setup do
    TestRedis.setup
    on_exit fn ->
      TestRedis.teardown
    end
  end

  def assert_dequeue_job(queues, expected_result) do
    jobs = JobQueue.dequeue(:testredis, "test", @host, queues)
    result = jobs |> Enum.reject(fn({:ok, {status, _}}) -> status == :none end)
    if is_boolean(expected_result) do
      assert expected_result == !Enum.empty?(result)
    else
      assert expected_result == Enum.count(result)
    end
  end

  test "enqueue/dequeue single queue" do
    JobQueue.enqueue(:testredis, "test", "default", MyWorker, [])
    [{:ok, {deq, _}}] = JobQueue.dequeue(:testredis, "test", @host, ["default"])
    assert deq != :none
    [{:ok, {deq, _}}] = JobQueue.dequeue(:testredis, "test", @host, ["default"])
    assert deq == :none
  end

  test "enqueue/dequeue multi queue" do
    JobQueue.enqueue(:testredis, "test", "default", MyWorker, [])
    JobQueue.enqueue(:testredis, "test", "myqueue", MyWorker, [])
    assert_dequeue_job(["default", "myqueue"], 2)
    assert_dequeue_job(["default", "myqueue"], false)
  end

  test "backup queue" do
    JobQueue.enqueue(:testredis, "test", "default", MyWorker, [])
    JobQueue.enqueue(:testredis, "test", "default", MyWorker, [])
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], false)
    JobQueue.re_enqueue_backup(:testredis, "test", @host, "default")
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], false)
  end

  test "remove from backup queue" do
    JobQueue.enqueue(:testredis, "test", "default", MyWorker, [])
    JobQueue.enqueue(:testredis, "test", "default", MyWorker, [])

    [{:ok, {job, _}}] = JobQueue.dequeue(:testredis, "test", @host, ["default"])
    assert_dequeue_job(["default"], true)

    # remove job from queue
    JobQueue.remove_job_from_backup(:testredis, "test", @host, "default", job)

    # should only have 1 job now
    JobQueue.re_enqueue_backup(:testredis, "test", @host, "default")

    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], false)
  end

  test "scheduler_dequeue single queue" do
    JobQueue.enqueue_in(:testredis, "test", "default", 0, MyWorker, [])
    JobQueue.enqueue_in(:testredis, "test", "default", 0, MyWorker, [])
    assert JobQueue.scheduler_dequeue(:testredis, "test") == 2
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], false)
  end

  test "scheduler_dequeue multi queue" do
    JobQueue.enqueue_in(:testredis, "test", "default", -1, MyWorker, [])
    JobQueue.enqueue_in(:testredis, "test", "myqueue", -1, MyWorker, [])
    assert JobQueue.scheduler_dequeue(:testredis, "test") == 2
    assert_dequeue_job(["default", "myqueue"], 2)
    assert_dequeue_job(["default", "myqueue"], false)
  end

  test "scheduler_dequeue enqueue_at" do
    JobQueue.enqueue_at(:testredis, "test", "default", DateTime.utc_now, MyWorker, [])
    {jid, job_serialized} = JobQueue.to_job_serialized("retry", MyWorker, [], retry: true)
    JobQueue.enqueue_job_at(:testredis, "test", job_serialized, jid, DateTime.utc_now, "test:retry")
    assert JobQueue.scheduler_dequeue(:testredis, "test") == 2
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], false)

    assert_dequeue_job(["retry"], true)
    assert_dequeue_job(["retry"], false)
  end

  test "scheduler_dequeue max_score" do
    add_usecs = fn(time, offset) ->
      base = time |> DateTime.to_unix(:microseconds)
      DateTime.from_unix!(base + offset, :microseconds)
    end

    JobQueue.enqueue_in(:testredis, "test", "default", 300, MyWorker, [])
    now = DateTime.utc_now
    time1 = add_usecs.(now, 140_000_000)
    JobQueue.enqueue_at(:testredis, "test", "default", time1, MyWorker, [])
    time2 = add_usecs.(now, 150_000_000)
    JobQueue.enqueue_at(:testredis, "test", "default", time2, MyWorker, [])
    time2a = add_usecs.(now, 151_000_000)
    time2b = add_usecs.(now, 159_000_000)
    time3 = add_usecs.(now, 160_000_000)
    JobQueue.enqueue_at(:testredis, "test", "default", time3, MyWorker, [])
    time4 = add_usecs.(now, 160_000_001)
    JobQueue.enqueue_at(:testredis, "test", "default", time4, MyWorker, [])
    time5 = add_usecs.(now, 300_000_000)

    api_state = %Exq.Api.Server.State{redis: :testredis, namespace: "test"}
    assert JobQueue.queue_size(api_state.redis, api_state.namespace, "default") == 0
    assert JobQueue.queue_size(api_state.redis, api_state.namespace, :scheduled) == 5

    assert JobQueue.scheduler_dequeue(:testredis, "test", Time.time_to_score(time2a)) == 2
    assert JobQueue.scheduler_dequeue(:testredis, "test", Time.time_to_score(time2b)) == 0
    assert JobQueue.scheduler_dequeue(:testredis, "test", Time.time_to_score(time3)) == 1
    assert JobQueue.scheduler_dequeue(:testredis, "test", Time.time_to_score(time3)) == 0
    assert JobQueue.scheduler_dequeue(:testredis, "test", Time.time_to_score(time4)) == 1
    assert JobQueue.scheduler_dequeue(:testredis, "test", Time.time_to_score(time5)) == 1

    assert JobQueue.queue_size(api_state.redis, api_state.namespace, "default") == 5
    assert JobQueue.queue_size(api_state.redis, api_state.namespace, :scheduled) == 0


    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], false)
  end

  test "full_key" do
    assert JobQueue.full_key("exq","k1") == "exq:k1"
    assert JobQueue.full_key("","k1") == "k1"
    assert JobQueue.full_key(nil,"k1") == "k1"
  end

  test "creates and returns a jid" do
    {:ok, jid} = JobQueue.enqueue(:testredis, "test", "default", MyWorker, [])
    assert jid != nil

    [{:ok, {job_str, _}}] = JobQueue.dequeue(:testredis, "test", @host, ["default"])
    job = Poison.decode!(job_str, as: %Exq.Support.Job{})
    assert job.jid == jid
  end

  test "to_job_serialized using module atom" do
    {_jid, serialized} = JobQueue.to_job_serialized("default", MyWorker, [], retry: true)
    job = Job.decode(serialized)
    assert job.class == "MyWorker"
  end

  test "to_job_serialized using module string" do
    {_jid, serialized} = JobQueue.to_job_serialized("default", "MyWorker/perform", [], retry: true)
    job = Job.decode(serialized)
    assert job.class == "MyWorker/perform"
  end
end
