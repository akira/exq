use Mix.Config

config :logger, :console,
  format: "\n$date $time [$level]: $message \n"

config :exq,
  name: Exq,
  host: "127.0.0.1",
  port: 6379,
  namespace: "exq",
  database: 0,
  queues: ["default"],
  scheduler_enable: true,
  concurrency: 100,
  scheduler_poll_timeout: 200,
  poll_timeout: 100,
  redis_timeout: 5000,
  genserver_timeout: 5000,
  reconnect_on_sleep: 100,
  max_retries: 25,
  middleware: [Exq.Middleware.Stats, Exq.Middleware.Job, Exq.Middleware.Manager,
    Exq.Middleware.Logger]

import_config "#{Mix.env}.exs"
