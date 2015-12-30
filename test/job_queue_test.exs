Code.require_file "test_helper.exs", __DIR__

defmodule JobQueueTest do
  use ExUnit.Case
  use Timex
  alias Exq.Redis.JobQueue
  alias Exq.Support.Job

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
    JobQueue.enqueue_at(:testredis, "test", "default", Time.now, MyWorker, [])
    assert JobQueue.scheduler_dequeue(:testredis, "test") == 1
    assert_dequeue_job(["default"], true)
    assert_dequeue_job(["default"], false)
  end

  test "scheduler_dequeue max_score" do
    JobQueue.enqueue_in(:testredis, "test", "default", 300, MyWorker, [])
    now = Time.now
    time1 = Time.add(now, Time.from(140, :secs))
    JobQueue.enqueue_at(:testredis, "test", "default", time1, MyWorker, [])
    time2 = Time.add(now, Time.from(150, :secs))
    JobQueue.enqueue_at(:testredis, "test", "default", time2, MyWorker, [])
    time2a = Time.add(now, Time.from(151, :secs))
    time2b = Time.add(now, Time.from(159, :secs))
    time3 = Time.add(now, Time.from(160, :secs))
    JobQueue.enqueue_at(:testredis, "test", "default", time3, MyWorker, [])
    time4 = Time.add(now, Time.from(160000001, :usecs))
    JobQueue.enqueue_at(:testredis, "test", "default", time4, MyWorker, [])
    time5 = Time.add(now, Time.from(300, :secs))

    assert Exq.Enqueuer.Server.queue_size(:testredis, "test", "default") == 0
    assert Exq.Enqueuer.Server.queue_size(:testredis, "test", :scheduled) == 5

    assert JobQueue.scheduler_dequeue(:testredis, "test", JobQueue.time_to_score(time2a)) == 2
    assert JobQueue.scheduler_dequeue(:testredis, "test", JobQueue.time_to_score(time2b)) == 0
    assert JobQueue.scheduler_dequeue(:testredis, "test", JobQueue.time_to_score(time3)) == 1
    assert JobQueue.scheduler_dequeue(:testredis, "test", JobQueue.time_to_score(time3)) == 0
    assert JobQueue.scheduler_dequeue(:testredis, "test", JobQueue.time_to_score(time4)) == 1
    assert JobQueue.scheduler_dequeue(:testredis, "test", JobQueue.time_to_score(time5)) == 1

    assert Exq.Enqueuer.Server.queue_size(:testredis, "test", "default") == 5
    assert Exq.Enqueuer.Server.queue_size(:testredis, "test", :scheduled) == 0


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
    job = Poison.decode!(job_str, as: Exq.Support.Job)
    assert job.jid == jid
  end

  test "to_job_json using module atom" do
    {_jid, json} = JobQueue.to_job_json("default", MyWorker, [])
    job = Job.from_json(json)
    assert job.class == "MyWorker"
  end

  test "to_job_json using module string" do
    {_jid, json} = JobQueue.to_job_json("default", "MyWorker/perform", [])
    job = Job.from_json(json)
    assert job.class == "MyWorker/perform"
  end
end
