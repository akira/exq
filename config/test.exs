use Mix.Config

config :logger, :console,
  format: "\n$date $time [$level]: $message \n"

config :exq,
  host: String.to_char_list(System.get_env("REDIS_HOST") || "127.0.0.1"),
  port: String.to_integer(System.get_env("REDIS_PORT") || "6555"),
  namespace: "exq",
  queues: ["default"],
  scheduler_enable: false,
  scheduler_poll_timeout: 200,
  redis_timeout: 5000,
  genserver_timeout: 5000,
  test_with_local_redis: true
