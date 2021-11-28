defmodule Exq.Support.Opts do
  @moduledoc """
  Exq supported options.
  """

  alias Exq.Support.Coercion
  alias Exq.Support.Config

  @doc """
  Returns top supervisor's name default is `Exq.Sup`.
  """
  def top_supervisor(name) do
    name = name || Config.get(:name)
    "#{name}.Sup" |> String.to_atom()
  end

  defp conform_opts(opts) do
    mode = opts[:mode] || Config.get(:mode)
    redis = redis_client_name(opts[:name])
    opts = [{:redis, redis} | opts]

    redis_opts = redis_opts(opts)
    server_opts = server_opts(mode, opts)
    {redis_opts, server_opts}
  end

  def redis_client_name(name) do
    name = name || Config.get(:name)
    "#{name}.Redis.Client" |> String.to_atom()
  end

  def redis_inspect_opts(opts \\ []) do
    args = redis_opts(opts)

    case args do
      [url, options] -> [url, mask_password(options)]
      [options] -> [mask_password(options)]
    end
    |> inspect()
  end

  def redis_opts(opts \\ []) do
    redis_options = opts[:redis_options] || Config.get(:redis_options)
    socket_opts = opts[:socket_opts] || Config.get(:socket_opts) || []

    redis_options =
      Keyword.merge(
        [name: opts[:redis], socket_opts: socket_opts],
        redis_options
      )

    if url = opts[:url] || Config.get(:url) do
      [url, redis_options]
    else
      if Keyword.has_key?(redis_options, :sentinel) do
        [redis_options]
      else
        host = opts[:host] || Config.get(:host)
        port = Coercion.to_integer(opts[:port] || Config.get(:port))
        database = Coercion.to_integer(opts[:database] || Config.get(:database))
        password = opts[:password] || Config.get(:password)

        [
          Keyword.merge(
            [host: host, port: port, database: database, password: password],
            redis_options
          )
        ]
      end
    end
  end

  @doc """
  Returns `{redis_module, redis_args, gen_server_opts}`.
  """
  def redis_worker_opts(opts) do
    {redis_opts, opts} = conform_opts(opts)
    {Redix, redis_opts, opts}
  end

  defp mask_password(options) do
    options =
      if Keyword.has_key?(options, :password) do
        Keyword.update!(options, :password, fn
          nil -> nil
          _ -> "*****"
        end)
      else
        options
      end

    options =
      if Keyword.has_key?(options, :sentinel) do
        Keyword.update!(options, :sentinel, &mask_password/1)
      else
        options
      end

    if Keyword.has_key?(options, :sentinels) do
      Keyword.update!(options, :sentinels, fn sentinels ->
        Enum.map(sentinels, &mask_password/1)
      end)
    else
      options
    end
  end

  defp server_opts(:default, opts) do
    scheduler_enable =
      Coercion.to_boolean(opts[:scheduler_enable] || Config.get(:scheduler_enable))

    namespace = opts[:namespace] || Config.get(:namespace)

    scheduler_poll_timeout =
      Coercion.to_integer(opts[:scheduler_poll_timeout] || Config.get(:scheduler_poll_timeout))

    poll_timeout = Coercion.to_integer(opts[:poll_timeout] || Config.get(:poll_timeout))

    shutdown_timeout =
      Coercion.to_integer(opts[:shutdown_timeout] || Config.get(:shutdown_timeout))

    manager = Exq.Manager.Server.server_name(opts[:name])
    enqueuer = Exq.Enqueuer.Server.server_name(opts[:name])
    stats = Exq.Stats.Server.server_name(opts[:name])
    scheduler = Exq.Scheduler.Server.server_name(opts[:name])
    workers_sup = Exq.Worker.Supervisor.supervisor_name(opts[:name])
    middleware = Exq.Middleware.Server.server_name(opts[:name])
    metadata = Exq.Worker.Metadata.server_name(opts[:name])

    queue_configs = opts[:queues] || Config.get(:queues)
    per_queue_concurrency = cast_concurrency(opts[:concurrency] || Config.get(:concurrency))
    queues = get_queues(queue_configs)
    concurrency = get_concurrency(queue_configs, per_queue_concurrency)
    default_middleware = Config.get(:middleware)

    heartbeat_enable =
      Coercion.to_boolean(Keyword.get(opts, :heartbeat_enable, Config.get(:heartbeat_enable)))

    heartbeat_interval =
      Coercion.to_integer(opts[:heartbeat_interval] || Config.get(:heartbeat_interval))

    missed_heartbeats_allowed =
      Coercion.to_integer(
        opts[:missed_heartbeats_allowed] || Config.get(:missed_heartbeats_allowed)
      )

    [
      scheduler_enable: scheduler_enable,
      namespace: namespace,
      scheduler_poll_timeout: scheduler_poll_timeout,
      workers_sup: workers_sup,
      poll_timeout: poll_timeout,
      enqueuer: enqueuer,
      metadata: metadata,
      stats: stats,
      name: opts[:name],
      manager: manager,
      scheduler: scheduler,
      queues: queues,
      redis: opts[:redis],
      concurrency: concurrency,
      middleware: middleware,
      default_middleware: default_middleware,
      mode: :default,
      shutdown_timeout: shutdown_timeout,
      heartbeat_enable: heartbeat_enable,
      heartbeat_interval: heartbeat_interval,
      missed_heartbeats_allowed: missed_heartbeats_allowed
    ]
  end

  defp server_opts(mode, opts) do
    namespace = opts[:namespace] || Config.get(:namespace)
    [name: opts[:name], namespace: namespace, redis: opts[:redis], mode: mode]
  end

  defp get_queues(queue_configs) do
    Enum.map(queue_configs, fn queue_config ->
      case queue_config do
        {queue, _concurrency} -> queue
        queue -> queue
      end
    end)
  end

  defp get_concurrency(queue_configs, per_queue_concurrency) do
    Enum.map(queue_configs, fn queue_config ->
      case queue_config do
        {queue, concurrency} -> {queue, cast_concurrency(concurrency)}
        queue -> {queue, per_queue_concurrency}
      end
    end)
  end

  def cast_concurrency({module, options}), do: {module, options}
  def cast_concurrency(:infinity), do: {Exq.Dequeue.Local, [concurrency: :infinity]}
  def cast_concurrency(:infinite), do: {Exq.Dequeue.Local, [concurrency: :infinity]}
  def cast_concurrency(x) when is_integer(x), do: {Exq.Dequeue.Local, [concurrency: x]}

  def cast_concurrency(x) when is_binary(x) do
    case x |> String.trim() |> String.downcase() do
      "infinity" -> {Exq.Dequeue.Local, [concurrency: :infinity]}
      "infinite" -> {Exq.Dequeue.Local, [concurrency: :infinity]}
      x -> {Exq.Dequeue.Local, [concurrency: Coercion.to_integer(x)]}
    end
  end
end
