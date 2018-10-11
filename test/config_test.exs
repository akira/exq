defmodule Exq.ConfigTest do
  use ExUnit.Case
  require Mix.Config
  import ExqTestUtil

  setup_all do
    ExqTestUtil.reset_config
    :ok
  end

  setup do
    env = System.get_env

    on_exit fn ->
      ExqTestUtil.reset_env(env)
      ExqTestUtil.reset_config
    end
  end

  test "Mix.Config should change the host." do
    assert Exq.Support.Config.get(:host) != "127.1.1.1"
    Mix.Config.persist([exq: [host: "127.1.1.1"]])
    assert Exq.Support.Config.get(:host) == "127.1.1.1"
  end

  test "redis_opts from runtime environment" do
    System.put_env("REDIS_HOST", "127.0.0.1")
    System.put_env("REDIS_PORT", "6379")
    System.put_env("REDIS_DATABASE", "1")
    System.put_env("REDIS_PASSWORD", "password")

    Mix.Config.persist([
      exq: [
        host: {:system, "REDIS_HOST"},
        port: {:system, "REDIS_PORT"},
        database: {:system, "REDIS_DATABASE"},
        password: {:system, "REDIS_PASSWORD"}
      ]
    ])

    [
      host: host,
      port: port,
      database: database,
      password: password
    ] = Exq.Support.Opts.redis_opts

    assert host == "127.0.0.1"
    assert port == 6379
    assert database == 1
    assert password == "password"

    System.put_env("REDIS_URL", "redis_url")
    Mix.Config.persist([exq: [url: {:system, "REDIS_URL"}]])
    redis_opts = Exq.Support.Opts.redis_opts
    assert redis_opts == "redis_url"
  end

  test "redis_opts from runtime with defaults" do
    Mix.Config.persist([exq: [url: {:system, "REDIS_URL", "default_redis_url"}]])

    redis_opts = Exq.Support.Opts.redis_opts
    assert redis_opts == "default_redis_url"
  end

  test "Raises an ArgumentError when supplied with an invalid port" do
    Mix.Config.persist([exq: [port: {:system, "REDIS_PORT"}]])
    System.put_env("REDIS_PORT", "invalid integer")

    assert_raise(ArgumentError, fn ->
      Exq.Support.Opts.redis_opts
    end)
  end

  test "redis_opts" do
    Mix.Config.persist([exq: [host: "127.0.0.1", port: 6379, password: '', database: 0]])
    [host: host, port: port, database: database, password: password] = Exq.Support.Opts.redis_opts

    assert host == "127.0.0.1"
    assert port == 6379
    assert password == ''
    assert database == 0

    Mix.Config.persist([exq: [host: '127.1.1.1', password: 'password']])
    redis_opts = Exq.Support.Opts.redis_opts
    assert redis_opts[:host] == '127.1.1.1'
    assert redis_opts[:password] == 'password'

    Mix.Config.persist([exq: [password: "binary_password"]])
    redis_opts = Exq.Support.Opts.redis_opts
    assert redis_opts[:password] == "binary_password"

    Mix.Config.persist([exq: [password: nil]])
    redis_opts = Exq.Support.Opts.redis_opts
    assert redis_opts[:password] == nil

    Mix.Config.persist([exq: [url: "redis_url"]])
    redis_opts = Exq.Support.Opts.redis_opts
    assert redis_opts == "redis_url"
  end

  test "connection_opts" do
    Mix.Config.persist([exq: [redis_options: [backoff_initial: 100, sync_connect: true]]])
    [name: client_name, socket_opts: [], backoff_initial: backoff_initial, sync_connect: sync_connect] = Exq.Support.Opts.connection_opts

    assert backoff_initial == 100
    assert sync_connect == true
    assert client_name == nil
  end

  test "default redis_worker_opts" do
    Mix.Config.persist([
      exq: [
        queues: ["default"],
        scheduler_enable: true,
        namespace: "exq",
        concurrency: 100,
        scheduler_poll_timeout: 200,
        poll_timeout: 100,
        redis_timeout: 5000,
        shutdown_timeout: 7000,
      ]
    ])
    {Redix, [_redis_opts, _connection_opts], server_opts} = Exq.Support.Opts.redis_worker_opts([mode: :default])
    [scheduler_enable: scheduler_enable, namespace: namespace, scheduler_poll_timeout: scheduler_poll_timeout,
     workers_sup: workers_sup, poll_timeout: poll_timeout, enqueuer: enqueuer, metadata: metadata, stats: stats,
     name: name, scheduler: scheduler, queues: queues, redis: redis, concurrency: concurrency, middleware: middleware,
     default_middleware: default_middleware, mode: mode, shutdown_timeout: shutdown_timeout]
    = server_opts
    assert scheduler_enable == true
    assert namespace == "exq"
    assert scheduler_poll_timeout == 200
    assert workers_sup == Exq.Worker.Sup
    assert poll_timeout == 100
    assert shutdown_timeout == 7000
    assert enqueuer == Exq.Enqueuer
    assert stats == Exq.Stats
    assert name == nil
    assert scheduler == Exq.Scheduler
    assert metadata == Exq.Worker.Metadata
    assert queues == ["default"]
    assert redis == Exq.Redis.Client
    assert concurrency == [{"default", 100, 0}]
    assert middleware == Exq.Middleware.Server
    assert default_middleware == [Exq.Middleware.Stats, Exq.Middleware.Job, Exq.Middleware.Manager]
    assert mode == :default

    Mix.Config.persist([exq: [queues: [{"default", 1000}, {"test1", 2000}]]])
    {Redix, [_redis_opts, _connection_opts], server_opts} = Exq.Support.Opts.redis_worker_opts([mode: :default])
    assert server_opts[:queues] == ["default", "test1"]
    assert server_opts[:concurrency] == [{"default", 1000, 0}, {"test1", 2000, 0}]
  end

  test "api redis_worker_opts" do
    Mix.Config.persist([exq: []])
    {Redix, [_redis_opts, _connection_opts], server_opts} = Exq.Support.Opts.redis_worker_opts([mode: :api])
    [name: name, namespace: namespace, redis: redis, mode: mode] = server_opts
    assert namespace == "test"
    assert name == nil
    assert redis == Exq.Redis.Client
    assert mode == :api
  end

  test "redis_worker_opts from runtime environment" do
    System.put_env("EXQ_NAMESPACE", "test")
    System.put_env("EXQ_CONCURRENCY", "333")
    System.put_env("EXQ_POLL_TIMEOUT", "17")
    System.put_env("EXQ_SCHEDULER_POLL_TIMEOUT", "123")
    System.put_env("EXQ_SCHEDULER_ENABLE", "True")
    System.put_env("EXQ_SHUTDOWN_TIMEOUT", "1234")

    Mix.Config.persist([
      exq: [
        namespace: {:system, "EXQ_NAMESPACE"},
        concurrency: {:system, "EXQ_CONCURRENCY"},
        poll_timeout: {:system, "EXQ_POLL_TIMEOUT"},
        scheduler_poll_timeout: {:system, "EXQ_SCHEDULER_POLL_TIMEOUT"},
        scheduler_enable: {:system, "EXQ_SCHEDULER_ENABLE"},
        shutdown_timeout: {:system, "EXQ_SHUTDOWN_TIMEOUT"}
      ]
    ])

    {Redix, [_redis_opts, _connection_opts], server_opts} = Exq.Support.Opts.redis_worker_opts([mode: :default])

    assert server_opts[:namespace] == "test"
    assert server_opts[:concurrency] == [{"default", 333, 0}]
    assert server_opts[:poll_timeout] == 17
    assert server_opts[:scheduler_poll_timeout] == 123
    assert server_opts[:scheduler_enable] == true
    assert server_opts[:shutdown_timeout] == 1234
  end

  test "redis_worker_opts from runtime environment - concurrency :infinity" do
    System.put_env("EXQ_CONCURRENCY", "infinity")

    Mix.Config.persist([
      exq: [
        concurrency: {:system, "EXQ_CONCURRENCY"},
      ]
    ])

    {Redix, [_redis_opts, _connection_opts], server_opts} = Exq.Support.Opts.redis_worker_opts([mode: :default])

    assert server_opts[:concurrency] == [{"default", :infinity, 0}]
  end

  test "custom redis module" do
    with_application_env(:exq, :redis_worker, {RedisWorker, [1, 2]}, fn ->
      {module, args, _server_opts} = Exq.Support.Opts.redis_worker_opts([mode: :default])
      assert module == RedisWorker
      assert args == [1, 2]
    end)
  end
end
