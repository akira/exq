Code.require_file "test_helper.exs", __DIR__

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

  test "info" do
    Mix.Config.persist([exq: [host: '127.0.0.1', port: 6379, password: '', database: 0, reconnect_on_sleep: 100, redis_timeout: 5000]])
    {[host: host, port: port, database: database, password: password],
      [backoff: reconnect_on_sleep, timeout: timeout, name: client_name]}
     = Exq.Manager.Supervisor.redix_opts
    assert host == '127.0.0.1'
    assert port == 6379
    assert password == ''
    assert database == 0
    assert reconnect_on_sleep == 100
    assert timeout == 5000
    assert client_name == nil

    Mix.Config.persist([exq: [host: '127.1.1.1', password: 'password']])
    {redis_opts, _} = Exq.Manager.Supervisor.redix_opts
    assert redis_opts[:host] == '127.1.1.1'
    assert redis_opts[:password] == 'password'

    Mix.Config.persist([exq: [password: "binary_password"]])

    {redis_opts, _} = Exq.Manager.Supervisor.redix_opts
    assert redis_opts[:password] == "binary_password"

    Mix.Config.persist([exq: [password: nil]])
    {redis_opts, _} = Exq.Manager.Supervisor.redix_opts
    assert redis_opts[:password] == nil

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
