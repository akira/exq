Code.require_file "test_helper.exs", __DIR__

defmodule RedisTest do
  use ExUnit.Case

  setup_all do 
    TestRedis.setup
  end 

  teardown_all do
    TestRedis.teardown
  end

  teardown do 
    Redis.flushdb! :testredis
    :ok
  end

  test "smembers empty" do 
    m = Redis.smembers!(:testredis, "bogus")
    assert m == []
  end
  
  test "sadd" do 
    r = Redis.sadd!(:testredis, "theset", "amember")
    assert r == "1"
    assert Redis.smembers!(:testredis, "theset") == ["amember"]
  end

  test "lpop empty" do 
    assert Redis.lpop!(:testredis, "bogus")  == nil
  end 

  test "rpush / lpop" do 
    Redis.rpush!(:testredis, "akey", "avalue")
    assert Redis.lpop!(:testredis, "akey")  == "avalue"
    assert Redis.lpop!(:testredis, "akey")  == nil
  end

  test "flushdb" do
    Redis.sadd!(:testredis, "theset", "amember")
    Redis.flushdb! :testredis
    assert Redis.smembers!(:testredis, "theset") == []
  end
end
