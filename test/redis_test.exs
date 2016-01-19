defmodule Exq.RedisTest do
  use ExUnit.Case

  alias Exq.Redis.Connection

  setup_all do
    ExqTestUtil.reset_config
    TestRedis.setup
    on_exit fn ->
      ExqTestUtil.reset_config
      TestRedis.teardown
    end
  end

  setup do
    on_exit fn ->
      Connection.flushdb! :testredis
    end
    :ok
  end

  test "smembers empty" do
    m = Connection.smembers!(:testredis, "bogus")
    assert m == []
  end

  test "sadd" do
    r = Connection.sadd!(:testredis, "theset", "amember")
    assert r == 1
    assert Connection.smembers!(:testredis, "theset") == ["amember"]
  end

  test "lpop empty" do
    assert Connection.lpop(:testredis, "bogus")  == {:ok, nil}
  end

  test "rpush / lpop" do
    Connection.rpush!(:testredis, "akey", "avalue")
    assert Connection.lpop(:testredis, "akey")  == {:ok, "avalue"}
    assert Connection.lpop(:testredis, "akey")  == {:ok, nil}
  end

  test "zadd / zcard / zrem" do
    assert Connection.zcard!(:testredis, "akey") == 0
    assert Connection.zadd!(:testredis, "akey", "1.7", "avalue") == 1
    assert Connection.zcard!(:testredis, "akey") == 1
    assert Connection.zrem!(:testredis, "akey", "avalue") == 1
    assert Connection.zcard!(:testredis, "akey") == 0
  end

  test "zrangebyscore" do
    assert Connection.zcard!(:testredis, "akey") == 0
    assert Connection.zadd!(:testredis, "akey", "123456.123455", "avalue") == 1
    assert Connection.zadd!(:testredis, "akey", "123456.123456", "bvalue") == 1
    assert Connection.zadd!(:testredis, "akey", "123456.123457", "cvalue") == 1

    assert Connection.zrangebyscore!(:testredis, "akey", 0, "111111.111111") == []
    assert Connection.zrangebyscore!(:testredis, "akey", 0, "123456.123455") == ["avalue"]
    assert Connection.zrangebyscore!(:testredis, "akey", 0, "123456.123456") == ["avalue", "bvalue"]
    assert Connection.zrangebyscore!(:testredis, "akey", 0, "123456.123457") == ["avalue", "bvalue", "cvalue"]
    assert Connection.zrangebyscore!(:testredis, "akey", 0, "999999.999999") == ["avalue", "bvalue", "cvalue"]

    assert Connection.zrem!(:testredis, "akey", "bvalue") == 1
    assert Connection.zrangebyscore!(:testredis, "akey", 0, "123456.123457") == ["avalue", "cvalue"]
    assert Connection.zrem!(:testredis, "akey", "avalue") == 1
    assert Connection.zrangebyscore!(:testredis, "akey", 0, "123456.123456") == []
    assert Connection.zrangebyscore!(:testredis, "akey", 0, "123456.123457") == ["cvalue"]
    assert Connection.zrem!(:testredis, "akey", "avalue") == 0
    assert Connection.zrem!(:testredis, "akey", "cvalue") == 1
    assert Connection.zrangebyscore!(:testredis, "akey", 0, "999999.999999") == []
  end

  test "flushdb" do
    Connection.sadd!(:testredis, "theset", "amember")
    Connection.flushdb! :testredis
    assert Connection.smembers!(:testredis, "theset") == []
  end
end
