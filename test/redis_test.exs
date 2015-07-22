Code.require_file "test_helper.exs", __DIR__

defmodule Exq.RedisTest do
  use ExUnit.Case

  setup_all do
    TestRedis.setup
    on_exit fn ->
      TestRedis.teardown
    end
  end

  setup do
    on_exit fn ->
      Exq.Redis.flushdb! :testredis
    end
    :ok
  end

  test "smembers empty" do
    m = Exq.Redis.smembers!(:testredis, "bogus")
    assert m == []
  end

  test "sadd" do
    r = Exq.Redis.sadd!(:testredis, "theset", "amember")
    assert r == "1"
    assert Exq.Redis.smembers!(:testredis, "theset") == ["amember"]
  end

  test "lpop empty" do
    assert Exq.Redis.lpop!(:testredis, "bogus")  == :none
  end

  test "rpush / lpop" do
    Exq.Redis.rpush!(:testredis, "akey", "avalue")
    assert Exq.Redis.lpop!(:testredis, "akey")  == "avalue"
    assert Exq.Redis.lpop!(:testredis, "akey")  == :none
  end

  test "zadd / zcard / zrem" do
    assert Exq.Redis.zcard!(:testredis, "akey") == "0"
    assert Exq.Redis.zadd!(:testredis, "akey", "1.7", "avalue") == "1"
    assert Exq.Redis.zcard!(:testredis, "akey") == "1"
    assert Exq.Redis.zrem!(:testredis, "akey", "avalue") == "1"
    assert Exq.Redis.zcard!(:testredis, "akey") == "0"
  end

  test "zrangebyscore" do
    assert Exq.Redis.zcard!(:testredis, "akey") == "0"
    assert Exq.Redis.zadd!(:testredis, "akey", "123456.123455", "avalue") == "1"
    assert Exq.Redis.zadd!(:testredis, "akey", "123456.123456", "bvalue") == "1"
    assert Exq.Redis.zadd!(:testredis, "akey", "123456.123457", "cvalue") == "1"

    assert Exq.Redis.zrangebyscore!(:testredis, "akey", 0, "111111.111111") == []
    assert Exq.Redis.zrangebyscore!(:testredis, "akey", 0, "123456.123455") == ["avalue"]
    assert Exq.Redis.zrangebyscore!(:testredis, "akey", 0, "123456.123456") == ["avalue", "bvalue"]
    assert Exq.Redis.zrangebyscore!(:testredis, "akey", 0, "123456.123457") == ["avalue", "bvalue", "cvalue"]
    assert Exq.Redis.zrangebyscore!(:testredis, "akey", 0, "999999.999999") == ["avalue", "bvalue", "cvalue"]

    assert Exq.Redis.zrem!(:testredis, "akey", "bvalue") == "1"
    assert Exq.Redis.zrangebyscore!(:testredis, "akey", 0, "123456.123457") == ["avalue", "cvalue"]
    assert Exq.Redis.zrem!(:testredis, "akey", "avalue") == "1"
    assert Exq.Redis.zrangebyscore!(:testredis, "akey", 0, "123456.123456") == []
    assert Exq.Redis.zrangebyscore!(:testredis, "akey", 0, "123456.123457") == ["cvalue"]
    assert Exq.Redis.zrem!(:testredis, "akey", "avalue") == "0"
    assert Exq.Redis.zrem!(:testredis, "akey", "cvalue") == "1"
    assert Exq.Redis.zrangebyscore!(:testredis, "akey", 0, "999999.999999") == []
  end

  test "flushdb" do
    Exq.Redis.sadd!(:testredis, "theset", "amember")
    Exq.Redis.flushdb! :testredis
    assert Exq.Redis.smembers!(:testredis, "theset") == []
  end
end
