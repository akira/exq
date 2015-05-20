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
    deq = Exq.RedisQueue.dequeue(:testredis, "test", "default")
    assert deq != :none
    assert Exq.RedisQueue.dequeue(:testredis, "test", "default") == :none
  end

  test "enqueue/dequeue multi queue" do
    Exq.RedisQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    Exq.RedisQueue.enqueue(:testredis, "test", "myqueue", "MyWorker", [])
    assert Exq.RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]) != :none
    assert Exq.RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]) != :none
    assert Exq.RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]) == :none
  end

  test "full_key" do
    assert Exq.RedisQueue.full_key("exq","k1") == "exq:k1"
    assert Exq.RedisQueue.full_key("","k1") == "k1"
    assert Exq.RedisQueue.full_key(nil,"k1") == "k1"
  end

  test "creates and returns a jid" do
    jid = Exq.RedisQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    assert jid != nil

    job_str = Exq.RedisQueue.dequeue(:testredis, "test", "default")
    job = Poison.decode!(job_str, as: Exq.Job)
    assert job.jid == jid
  end

end

