Code.require_file "test_helper.exs", __DIR__

defmodule RedisQueueTest do
  use ExUnit.Case

  setup_all do
    TestRedis.setup
  end 

  teardown_all do
    TestRedis.teardown
  end
 
  test "enqueue/dequeue single queue" do
    RedisQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    deq = RedisQueue.dequeue(:testredis, "test", "default")
    assert deq != :none 
    assert RedisQueue.dequeue(:testredis, "test", "default") == :none
  end
  
  test "enqueue/dequeue multi queue" do
    RedisQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    RedisQueue.enqueue(:testredis, "test", "myqueue", "MyWorker", [])
    assert RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]) != :none
    assert RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]) != :none
    assert RedisQueue.dequeue(:testredis, "test", ["default", "myqueue"]) == :none
  end
end

