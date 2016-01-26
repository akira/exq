defmodule Exq.Support.Config do
  @default_config %{
    name: Exq,
    host: "127.0.0.1",
    port: 6379,
    namespace: "exq",
    queues: ["default"],
    scheduler_enable: true,
    concurrency: 100,
    scheduler_poll_timeout: 200,
    poll_timeout: 100,
    redis_timeout: 5000,
    genserver_timeout: 5000,
    max_retries: 25
  }

  def get(key) do
    get(key, Map.get(@default_config, key))
  end

  def get(key, fallback) do
    Application.get_env(:exq, key, fallback)
  end
end
