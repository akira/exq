Code.require_file "test_helper.exs", __DIR__

defmodule Exq.RedisQueueTest do
  use ExUnit.Case

  setup_all do
    TestRedis.setup
  end 

  teardown_all do
    TestRedis.teardown
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
end

