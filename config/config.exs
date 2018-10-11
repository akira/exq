use Mix.Config

config :logger, :console,
  format: "\n$date $time [$level]: $message \n"

config :exq,
  name: Exq,
  host: "127.0.0.1",
  port: 6379,
  database: 0,
  redis_options: [],
  namespace: "exq",
  queues: ["default"],
  scheduler_enable: true,
  concurrency: 100,
  scheduler_poll_timeout: 200,
  poll_timeout: 100,
  genserver_timeout: 5000,
  shutdown_timeout: 5000,
  dead_max_jobs: 10_000,
  dead_timeout_in_seconds: 180 * 24 * 60 * 60, # 6 months
  max_retries: 25,
  middleware: [Exq.Middleware.Stats, Exq.Middleware.Job, Exq.Middleware.Manager,
    Exq.Middleware.Logger]

import_config "#{Mix.env}.exs"
