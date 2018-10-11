defmodule Exq.Support.Config do

  @default_config %{
    name: Exq,
    mode: :default,
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
    max_retries: 25,
    dead_max_jobs: 10_000,
    dead_timeout_in_seconds: 180 * 24 * 60 * 60, # 6 months
    stats_flush_interval: 1000,
    stats_batch_size: 2000,
    serializer: Exq.Serializers.JsonSerializer,
    node_identifier: Exq.NodeIdentifier.HostnameIdentifier,
    backoff: Exq.Backoff.SidekiqDefault,
    start_on_application: true,
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
    case Application.get_env(:exq, key, fallback) do
      {:system, varname} -> System.get_env(varname)
      {:system, varname, default} -> System.get_env(varname) || default
      value -> value
    end
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
