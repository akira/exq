use Mix.Config

config :logger, :console,
  format: "\n$date $time [$level]: $message \n"

config :exq,
  host: "127.0.0.1",
  port: 6379,
  namespace: "exq",
  queues: ["default"],
  scheduler_enable: true,
  concurrency: 10_000,
  scheduler_poll_timeout: 200,
  redis_timeout: 5000,
  genserver_timeout: 5000,
  max_retries: 25

import_config "#{Mix.env}.exs"
