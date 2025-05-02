import Config

config :logger, :console, format: "\n$date $time [$level]: $message \n"

config :exq,
  name: Exq,
  host: System.get_env("REDIS_HOST") || "127.0.0.1",
  port: System.get_env("REDIS_PORT") || 6555,
  url: nil,
  namespace: "test",
  queues: ["default"],
  heartbeat_enable: true,
  heartbeat_interval: 500,
  missed_heartbeats_allowed: 3,
  concurrency: :infinite,
  scheduler_enable: false,
  scheduler_poll_timeout: 20,
  poll_timeout: 10,
  redis_timeout: 5000,
  genserver_timeout: 5000,
  test_with_local_redis: true,
  max_retries: 0,
  stats_flush_interval: 5,
  stats_batch_size: 1,
  middleware: [
    Exq.Middleware.Stats,
    Exq.Middleware.Job,
    Exq.Middleware.Manager,
    Exq.Middleware.Unique,
    Exq.Middleware.Telemetry
  ],
  queue_adapter: Exq.Adapters.Queue.Mock
