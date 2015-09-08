Code.require_file "test_helper.exs", __DIR__

defmodule JobQueueTest do
  use ExUnit.Case
  use Timex
  alias Exq.Enqueuer
  alias Exq.Redis.JobQueue

  setup_all do
    TestRedis.setup
    on_exit fn ->
      TestRedis.teardown
    end
  end


  test "enqueue/dequeue single queue" do
    JobQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    {deq, _} = JobQueue.dequeue(:testredis, "test", "default")
    assert deq != :none
    {deq, _} = JobQueue.dequeue(:testredis, "test", "default")
    assert deq == :none
  end

  test "enqueue/dequeue multi queue" do
    JobQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    JobQueue.enqueue(:testredis, "test", "myqueue", "MyWorker", [])
    assert elem(JobQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) == :none
  end

  test "scheduler_dequeue single queue" do
    JobQueue.enqueue_in(:testredis, "test", "default", 0, "MyWorker", [])
    JobQueue.enqueue_in(:testredis, "test", "default", 0, "MyWorker", [])
    assert JobQueue.scheduler_dequeue(:testredis, "test", ["default"]) == 2
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) == :none
  end

  test "scheduler_dequeue multi queue" do
    JobQueue.enqueue_in(:testredis, "test", "default", -1, "MyWorker", [])
    JobQueue.enqueue_in(:testredis, "test", "myqueue", -1, "MyWorker", [])
    assert JobQueue.scheduler_dequeue(:testredis, "test", ["default", "myqueue"]) == 2
    assert elem(JobQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) == :none
  end

  test "scheduler_dequeue enqueue_at" do
    JobQueue.enqueue_at(:testredis, "test", "default", Time.now, "MyWorker", [])
    assert JobQueue.scheduler_dequeue(:testredis, "test", ["default"]) == 1
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) == :none
  end

  test "scheduler_dequeue max_score" do
    JobQueue.enqueue_in(:testredis, "test", "default", 300, "MyWorker", [])
    now = Time.now
    time1 = Time.add(now, Time.from(140, :secs))
    JobQueue.enqueue_at(:testredis, "test", "default", time1, "MyWorker", [])
    time2 = Time.add(now, Time.from(150, :secs))
    JobQueue.enqueue_at(:testredis, "test", "default", time2, "MyWorker", [])
    time2a = Time.add(now, Time.from(151, :secs))
    time2b = Time.add(now, Time.from(159, :secs))
    time3 = Time.add(now, Time.from(160, :secs))
    JobQueue.enqueue_at(:testredis, "test", "default", time3, "MyWorker", [])
    time4 = Time.add(now, Time.from(160000001, :usecs))
    JobQueue.enqueue_at(:testredis, "test", "default", time4, "MyWorker", [])
    time5 = Time.add(now, Time.from(300, :secs))

    assert Exq.Enqueuer.Server.queue_size(:testredis, "test", "default") == "0"
    assert Exq.Enqueuer.Server.queue_size(:testredis, "test", :scheduled) == "5"

    assert JobQueue.scheduler_dequeue(:testredis, "test", ["default"], JobQueue.time_to_score(time2a)) == 2
    assert JobQueue.scheduler_dequeue(:testredis, "test", ["default"], JobQueue.time_to_score(time2b)) == 0
    assert JobQueue.scheduler_dequeue(:testredis, "test", ["default"], JobQueue.time_to_score(time3)) == 1
    assert JobQueue.scheduler_dequeue(:testredis, "test", ["default"], JobQueue.time_to_score(time3)) == 0
    assert JobQueue.scheduler_dequeue(:testredis, "test", ["default"], JobQueue.time_to_score(time4)) == 1
    assert JobQueue.scheduler_dequeue(:testredis, "test", ["default"], JobQueue.time_to_score(time5)) == 1

    assert Exq.Enqueuer.Server.queue_size(:testredis, "test", "default") == "5"
    assert Exq.Enqueuer.Server.queue_size(:testredis, "test", :scheduled) == "0"

    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) != :none
    assert elem(JobQueue.dequeue(:testredis, "test", "default"), 0) == :none
  end

  test "full_key" do
    assert JobQueue.full_key("exq","k1") == "exq:k1"
    assert JobQueue.full_key("","k1") == "k1"
    assert JobQueue.full_key(nil,"k1") == "k1"
  end

  test "creates and returns a jid" do
    jid = JobQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    assert jid != nil

    {job_str, _} = JobQueue.dequeue(:testredis, "test", "default")
    job = Poison.decode!(job_str, as: Exq.Support.Job)
    assert job.jid == jid
  end

end
