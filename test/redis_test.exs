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

  test "sismember" do
    _ = Connection.sadd!(:testredis, "theset", "amember")
    _ = Connection.sadd!(:testredis, "theset", "anothermember")
    assert 1 == Connection.sismember!(:testredis, "theset", "amember")
    assert 1 == Connection.sismember!(:testredis, "theset", "anothermember")
    assert 0 == Connection.sismember!(:testredis, "theset", "not_a_member")
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

  test "zcount" do
    assert Connection.zcount!(:testredis, "akey") == Connection.zcard!(:testredis, "akey")
    assert Connection.zadd!(:testredis, "akey", "1", "avalue") == 1
    assert Connection.zadd!(:testredis, "akey", "1", "bvalue") == 1
    assert Connection.zadd!(:testredis, "akey", "2", "cvalue") == 1

    assert Connection.zcount!(:testredis, "akey", "0", "1") == 2
    assert Connection.zcount!(:testredis, "akey", "1", "1") == 2
    assert Connection.zcount!(:testredis, "akey", "-inf", "+inf") == 3
    assert Connection.zcount!(:testredis, "akey", "1", "(2") == 2
    assert Connection.zcount!(:testredis, "akey", "(1", "2") == 1
  end

  test "flushdb" do
    Connection.sadd!(:testredis, "theset", "amember")
    Connection.flushdb! :testredis
    assert Connection.smembers!(:testredis, "theset") == []
  end

  test "prepare_script" do
    assert Connection.prepare_script("return 0") == {:lua_script, "06d3d9b2060dd51343d5f19f0e531f15c507e3d1", "return 0"}
  end

  test "eval!" do
    script_with_arity_0 = Connection.prepare_script("return 0")
    assert Connection.eval!(:testredis, script_with_arity_0, []) == 0
    assert Connection.eval!(:testredis, script_with_arity_0, ["any", "args"]) == 0

    script_with_arity_1 = Connection.prepare_script("return KEYS[1]")
    assert Connection.eval!(:testredis, script_with_arity_1, []) == nil
    assert Connection.eval!(:testredis, script_with_arity_1, ["any", "args"]) == "any"

    multiple_return_script = Connection.prepare_script("return {1, 2}")
    assert Connection.eval!(:testredis, multiple_return_script, []) == [1, 2]

    crashing_script = Connection.prepare_script("invalid")
    assert_raise Redix.Error, ~r/^ERR Error compiling script/, fn ->
      Connection.eval!(:testredis, crashing_script, [])
    end
  end
end
