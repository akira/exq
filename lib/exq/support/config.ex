defmodule Exq.Support.Config do

  @default_config %{
    name: Exq,
    mode: :default,
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
    shutdown_timeout: 5000,
    reconnect_on_sleep: 100,
    max_retries: 25,
    stats_flush_interval: 1000,
    stats_batch_size: 2000,
    serializer: Exq.Serializers.JsonSerializer,
    node_identifier: Exq.NodeIdentifier.HostnameIdentifier,
    backoff: Exq.Backoff.SidekiqDefault,
    middleware: [
      Exq.Middleware.Stats,
      Exq.Middleware.Job,
      Exq.Middleware.Manager,
      Exq.Middleware.Logger
    ]
  }

  def get(key) do
    get(key, Map.get(@default_config, key))
  end

  def get(key, fallback) do
    Application.get_env(:exq, key, fallback)
  end

  def serializer do
    get(:serializer)
  end

  def node_identifier do
    get(:node_identifier)
  end

  def backoff() do
    get(:backoff)
  end
end
