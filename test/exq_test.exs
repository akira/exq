Code.require_file "test_helper.exs", __DIR__

defmodule ExqTest do
  use ExUnit.Case

  setup do
    TestRedis.start
    :ok
  end 

  teardown do
    TestRedis.stop
    #TestRedis.flush_all
    :ok
  end
  
  test "start with defaults" do
    {:ok, exq} = Exq.start([port: 6555 ])
    Exq.stop(exq)
    :timer.sleep(10)
  end
  
  test "enqueue with pid" do
    {:ok, exq} = Exq.start([port: 6555 ])
    {:ok, "1"} = Exq.enqueue(exq, "default", "MyJob", [1, 2, 3])
    Exq.stop(exq)
    :timer.sleep(10)
  end
end
