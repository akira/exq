use Mix.Config

config :logger, :console,
  format: "\n$date $time [$level]: $message \n"

config :exq,
  host: '127.0.0.1',
  port: 6379,
  namespace: "exq",
  queues: ["default"],
  scheduler_enable: false,
  scheduler_poll_timeout: 200
