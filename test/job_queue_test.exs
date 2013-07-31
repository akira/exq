Code.require_file "test_helper.exs", __DIR__

defmodule JobQueueTest do
  use ExUnit.Case

  setup_all do
    TestRedis.setup
  end 

  teardown_all do
    TestRedis.teardown
  end
 
  test "enqueue/dequeue single queue" do
    JobQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    deq = JobQueue.dequeue(:testredis, "test", "default")
    assert deq != nil 
    assert JobQueue.dequeue(:testredis, "test", "default") == nil
  end
  
  test "enqueue/dequeue multi queue" do
    JobQueue.enqueue(:testredis, "test", "default", "MyWorker", [])
    JobQueue.enqueue(:testredis, "test", "myqueue", "MyWorker", [])
    assert JobQueue.dequeue(:testredis, "test", ["default", "myqueue"]) != nil
    assert JobQueue.dequeue(:testredis, "test", ["default", "myqueue"]) != nil
    assert JobQueue.dequeue(:testredis, "test", ["default", "myqueue"]) == nil
  end
end

