defmodule Exq.ConfigTest do
  use ExUnit.Case
  require Mix.Config

  setup_all do
    ExqTestUtil.reset_config
    :ok
  end

  setup do
    on_exit fn -> ExqTestUtil.reset_config end
  end

  test "Mix.Config should change the host." do
    assert Exq.Support.Config.get(:host) != "127.1.1.1"
    Mix.Config.persist([exq: [host: "127.1.1.1"]])
    assert Exq.Support.Config.get(:host) == "127.1.1.1"
  end

  test "redis_opts" do
    Mix.Config.persist([exq: [host: '127.0.0.1', port: 6379, password: '', database: 0, reconnect_on_sleep: 100, redis_timeout: 5000]])
    {[host: host, port: port, database: database, password: password],
      [backoff: reconnect_on_sleep, timeout: timeout, name: client_name]}
     = Exq.Support.Opts.redis_opts
    assert host == '127.0.0.1'
    assert port == 6379
    assert password == ''
    assert database == 0
    assert reconnect_on_sleep == 100
    assert timeout == 5000
    assert client_name == nil

    Mix.Config.persist([exq: [host: '127.1.1.1', password: 'password']])
    {redis_opts, _} = Exq.Support.Opts.redis_opts
    assert redis_opts[:host] == '127.1.1.1'
    assert redis_opts[:password] == 'password'

    Mix.Config.persist([exq: [password: "binary_password"]])
    {redis_opts, _} = Exq.Support.Opts.redis_opts
    assert redis_opts[:password] == "binary_password"

    Mix.Config.persist([exq: [password: nil]])
    {redis_opts, _} = Exq.Support.Opts.redis_opts
    assert redis_opts[:password] == nil

    Mix.Config.persist([exq: [url: "redis_url"]])
    {redis_opts, _} = Exq.Support.Opts.redis_opts
    assert redis_opts == "redis_url"
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
    {_redis_opts, _connection_opts, server_opts} = Exq.Support.Opts.conform_opts
    [scheduler_enable: scheduler_enable, namespace: namespace, scheduler_poll_timeout: scheduler_poll_timeout,
      workers_sup: workers_sup, poll_timeout: poll_timeout, enqueuer: enqueuer, stats: stats, name: name,
      scheduler: scheduler, queues: queues, redis: redis, concurrency: concurrency, middleware: middleware,
      default_middleware: default_middleware]
    = server_opts
    assert scheduler_enable == true
    assert namespace == "exq"
    assert scheduler_poll_timeout == 200
    assert workers_sup == Exq.Worker.Sup
    assert poll_timeout == 100
    assert enqueuer == Exq.Enqueuer
    assert stats == Exq.Stats
    assert name == nil
    assert scheduler == Exq.Scheduler
    assert queues == ["default"]
    assert redis == Exq.Redis.Client
    assert concurrency == [{"default", 100, 0}]
    assert middleware == Exq.Middleware.Server
    assert default_middleware == [Exq.Middleware.Stats, Exq.Middleware.Job, Exq.Middleware.Manager]

    Mix.Config.persist([exq: [queues: [{"default", 1000}, {"test1", 2000}]]])
    {_redis_opts, _connection_opts, server_opts} = Exq.Support.Opts.conform_opts
    assert server_opts[:queues] == ["default", "test1"]
    assert server_opts[:concurrency] == [{"default", 1000, 0}, {"test1", 2000, 0}]

  end

end
