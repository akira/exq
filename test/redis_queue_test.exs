Code.require_file "test_helper.exs", __DIR__

defmodule Exq.RedisQueueTest do
  use ExUnit.Case

  setup_all do
    TestRedis.setup
    on_exit fn ->
      TestRedis.teardown
    end
  end


  test "enqueue/dequeue single queue" do
    Exq.RedisQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    {deq, _} = Exq.RedisQueue.dequeue(:testredis, "test", "default")
    assert deq != :none
    {deq, _} = Exq.RedisQueue.dequeue(:testredis, "test", "default")
    assert deq == :none
  end

  test "enqueue/dequeue multi queue" do
    Exq.RedisQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    Exq.RedisQueue.enqueue(:testredis, "test", "myqueue", "MyWorker", [])
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) != :none
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) != :none
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) == :none
  end

  test "scheduler_dequeue single queue" do
    Exq.RedisQueue.enqueue_in(:testredis, "test", "default", 0, "MyWorker", [])
    Exq.RedisQueue.enqueue_in(:testredis, "test", "default", 0, "MyWorker", [])
    assert Exq.RedisQueue.scheduler_dequeue(:testredis, "test", ["default"]) == 2
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default"]), 0) != :none
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default"]), 0) != :none
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default"]), 0) == :none
  end

  test "scheduler_dequeue multi queue" do
    Exq.RedisQueue.enqueue_in(:testredis, "test", "default", -1, "MyWorker", [])
    Exq.RedisQueue.enqueue_in(:testredis, "test", "myqueue", -1, "MyWorker", [])
    assert Exq.RedisQueue.scheduler_dequeue(:testredis, "test", ["default", "myqueue"]) == 2
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) != :none
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) != :none
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]), 0) == :none
  end

  test "enqueue_at" do
    Exq.RedisQueue.enqueue_at(:testredis, "test", "default", Timex.Time.now, "MyWorker", [])
    assert Exq.RedisQueue.scheduler_dequeue(:testredis, "test", ["default"]) == 1
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default"]), 0) != :none
    assert elem(Exq.RedisQueue.dequeue(:testredis, "test", ["default"]), 0) == :none
  end

  test "full_key" do
    assert Exq.RedisQueue.full_key("exq","k1") == "exq:k1"
    assert Exq.RedisQueue.full_key("","k1") == "k1"
    assert Exq.RedisQueue.full_key(nil,"k1") == "k1"
  end

  test "creates and returns a jid" do
    jid = Exq.RedisQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    assert jid != nil

    {job_str, _} = Exq.RedisQueue.dequeue(:testredis, "test", "default")
    job = Poison.decode!(job_str, as: Exq.Job)
    assert job.jid == jid
  end

end
