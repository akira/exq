defmodule Exq.Opts do

  alias Exq.Support.Config

  @default_timeout 5000

  @doc """
   Return top supervisor's name default is Exq.Sup
  """
  def top_supervisor(nil), do: Exq.Sup
  def top_supervisor(name), do: "#{name}.Sup" |> String.to_atom

  @doc """
   Return {redis_options, redis_connection_opts, gen_server_opts}
  """
  def conform_opts(opts \\[]) do
    redis = redis_client_name(opts[:name])
    opts = [{:redis, redis}|opts]
    {redis_opts, connection_opts} = redis_opts(opts)
    server_opts = server_opts(opts)
    {redis_opts, connection_opts, server_opts}
  end

  def redis_opts(opts \\ []) do
    host = opts[:host] || Config.get(:host, '127.0.0.1')
    port = opts[:port] || Config.get(:port, 6379)
    database = opts[:database] || Config.get(:database, 0)
    password = opts[:password] || Config.get(:password)
    reconnect_on_sleep = opts[:reconnect_on_sleep] || Config.get(:reconnect_on_sleep, 100)
    timeout = opts[:redis_timeout] || Config.get(:redis_timeout, @default_timeout)
    if is_binary(host), do: host = String.to_char_list(host)
    {[host: host, port: port, database: database, password: password],
     [backoff: reconnect_on_sleep, timeout: timeout, name: opts[:redis]]}
  end

  def redis_client_name(nil), do: Exq.Redis.Client
  def redis_client_name(name), do: "#{name}.Redis.Client" |> String.to_atom

  defp server_opts(opts) do
    scheduler_enable = opts[:scheduler_enable] || Config.get(:scheduler_enable, true)
    namespace = opts[:namespace] || Config.get(:namespace, "exq")
    scheduler_poll_timeout = opts[:scheduler_poll_timeout] || Config.get(:scheduler_poll_timeout, 200)
    poll_timeout = opts[:poll_timeout] || Config.get(:poll_timeout, 50)
    enqueuer = Exq.Enqueuer.Server.server_name(opts[:name])
    stats = Exq.Stats.Server.server_name(opts[:name])
    scheduler = Exq.Scheduler.Server.server_name(opts[:name])
    queues = get_queues(opts)
    concurrency = get_concurrency(opts)
    [scheduler_enable: scheduler_enable, namespace: namespace, scheduler_poll_timeout: scheduler_poll_timeout,
     poll_timeout: poll_timeout, enqueuer: enqueuer, stats: stats, name: opts[:name],
     scheduler: scheduler, queues: queues, redis: opts[:redis], concurrency: concurrency]
  end

  defp get_queues(opts) do
    queue_configs = opts[:queues] || Config.get(:queues, ["default"])
    Enum.map(queue_configs, fn queue_config ->
      case queue_config do
        {queue, _concurrency} -> queue
        queue -> queue
      end
    end)
  end

  defp get_concurrency(opts) do
    queue_configs = opts[:queues] || Config.get(:queues, ["default"])
    per_queue_concurrency = opts[:concurrency] || Config.get(:concurrency, 10_000)
    Enum.map(queue_configs, fn (queue_config) ->
        case queue_config do
          {queue, concurrency} -> {queue, concurrency, 0}
          queue -> {queue, per_queue_concurrency, 0}
        end
    end)
  end

end
