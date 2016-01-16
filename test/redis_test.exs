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

  test "redis_opts" do
    Mix.Config.persist([exq: [host: '127.0.0.1', port: 6379, password: '', database: 0, reconnect_on_sleep: 100, redis_timeout: 5000]])
    {[host: host, port: port, database: database, password: password],
      [backoff: reconnect_on_sleep, timeout: timeout, name: client_name]}
     = Exq.Opts.redis_opts
    assert host == '127.0.0.1'
    assert port == 6379
    assert password == ''
    assert database == 0
    assert reconnect_on_sleep == 100
    assert timeout == 5000
    assert client_name == nil

    Mix.Config.persist([exq: [host: '127.1.1.1', password: 'password']])
    {redis_opts, _} = Exq.Opts.redis_opts
    assert redis_opts[:host] == '127.1.1.1'
    assert redis_opts[:password] == 'password'

    Mix.Config.persist([exq: [password: "binary_password"]])

    {redis_opts, _} = Exq.Opts.redis_opts
    assert redis_opts[:password] == "binary_password"

    Mix.Config.persist([exq: [password: nil]])
    {redis_opts, _} = Exq.Opts.redis_opts
    assert redis_opts[:password] == nil

  end

test "conform_opts" do
    Mix.Config.persist([exq: [queues: ["default"],
     scheduler_enable: true,
     namespace: "exq",
     concurrency: 100,
     scheduler_poll_timeout: 200,
     poll_timeout: 100,
     redis_timeout: 5000,
     ]])
    {_redis_opts, _connection_opts, server_opts} = Exq.Opts.conform_opts
    [scheduler_enable: scheduler_enable, namespace: namespace, scheduler_poll_timeout: scheduler_poll_timeout,
      poll_timeout: poll_timeout, enqueuer: enqueuer, stats: stats, name: name,
      scheduler: scheduler, queues: queues, redis: redis, concurrency: concurrency]
    = server_opts
    assert scheduler_enable == true
    assert namespace == "exq"
    assert scheduler_poll_timeout == 200
    assert poll_timeout == 100
    assert enqueuer == Exq.Enqueuer
    assert stats == Exq.Stats
    assert name == nil
    assert scheduler == Exq.Scheduler
    assert queues == ["default"]
    assert redis == Exq.Redis.Client
    assert concurrency == [{"default", 100, 0}]

    Mix.Config.persist([exq: [queues: [{"default", 1000}, {"test1", 2000}]]])
    {_redis_opts, _connection_opts, server_opts} = Exq.Opts.conform_opts
    assert server_opts[:queues] == ["default", "test1"]
    assert server_opts[:concurrency] == [{"default", 1000, 0}, {"test1", 2000, 0}]

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
