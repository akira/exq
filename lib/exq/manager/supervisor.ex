defmodule Exq.Manager.Supervisor do
  use Supervisor

  alias Exq.Support.Config

  @default_timeout 5000

  def start(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: supervisor_name(opts[:name]))
  end

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: supervisor_name(opts[:name]))
  end

  def init(opts) do
    redis = redis_client_name(opts[:name])
    opts = [{:redis, redis}|opts]
    {redix_opts, connection_opts} = redix_opts(opts)
    opts = tidy_opts(opts)

    normal_children = [
      worker(Redix, [redix_opts, connection_opts]),
      worker(Exq.Stats.Server, [stats_opts(opts)]),
      worker(Exq.Enqueuer.Server, [enqueuer_opts(opts)]),
      supervisor(Exq.Worker.Supervisor, [opts]),
      worker(Exq.Manager.Server, [manager_opts(opts)]),
    ]

    scheduler_worker =
      case opts[:scheduler_enable] do
        true -> [worker(Exq.Scheduler.Server, [scheduler_opts(opts)])]
        false -> []
      end

    supervise(normal_children ++ scheduler_worker,
      strategy: :one_for_one,
      max_restarts: 20,
      max_seconds: 5)
  end

  def server_name(nil), do: Exq
  def server_name(name), do: name

  def supervisor_name(nil), do: Exq.Sup
  def supervisor_name(name), do: "#{name}.Sup" |> String.to_atom

  defp tidy_opts(opts) do
    scheduler_enable = Keyword.get(opts, :scheduler_enable, Config.get(:scheduler_enable, true))
    namespace = Keyword.get(opts, :namespace, Config.get(:namespace, "exq"))
    scheduler_poll_timeout = Keyword.get(opts, :scheduler_poll_timeout, Config.get(:scheduler_poll_timeout, 200))
    poll_timeout = Keyword.get(opts, :poll_timeout, Config.get(:poll_timeout, 50))
    enqueuer = Exq.Enqueuer.Server.server_name(opts[:name], :start_by_manager)
    stats = Exq.Stats.Server.server_name(opts[:name])
    scheduler = Exq.Scheduler.Server.server_name(opts[:name])
    queues = get_queues(opts)
    concurrency = get_concurrency(opts)
    [scheduler_enable: scheduler_enable, namespace: namespace, scheduler_poll_timeout: scheduler_poll_timeout,
     poll_timeout: poll_timeout, enqueuer: enqueuer, stats: stats, name: opts[:name],
     scheduler: scheduler, queues: queues, redis: opts[:redis], concurrency: concurrency]
  end

  def redix_opts(opts \\ []) do
    host = Keyword.get(opts, :host, Config.get(:host, '127.0.0.1'))
    port = Keyword.get(opts, :port, Config.get(:port, 6379))
    database = Keyword.get(opts, :database, Config.get(:database, 0))
    password = Keyword.get(opts, :password, Config.get(:password))
    reconnect_on_sleep = Keyword.get(opts, :reconnect_on_sleep, Config.get(:reconnect_on_sleep, 100))
    timeout = Keyword.get(opts, :redis_timeout, Config.get(:redis_timeout, @default_timeout))
    if is_binary(host), do: host = String.to_char_list(host)
    {[host: host, port: port, database: database, password: password],
     [backoff: reconnect_on_sleep, timeout: timeout, name: opts[:redis]]}
  end

  def redis_client_name(nil), do: Exq.Redis.Client
  def redis_client_name(name), do: "#{name}.Redis.Client" |> String.to_atom

  defp enqueuer_opts(opts) do
    [namespace: opts[:namespace], name: opts[:enqueuer], redis: opts[:redis]]
  end

  defp stats_opts(opts) do
    [redis: opts[:redis], name: opts[:stats]]
  end

  defp scheduler_opts(opts) do
    [redis: opts[:redis], name: opts[:scheduler], namespace: opts[:namespace],
     queues: opts[:queues], scheduler_poll_timeout: opts[:scheduler_poll_timeout]]
  end

  defp manager_opts(opts) do
    [enqueuer: opts[:enqueuer], namespace: opts[:namespace], name: opts[:name],
     poll_timeout: opts[:poll_timeout], queues: opts[:queues], redis: opts[:redis],
     scheduler_poll_timeout: opts[:scheduler_poll_timeout], concurrency: opts[:concurrency]]
  end

  defp get_queues(opts) do
    queue_configs = Keyword.get(opts, :queues, Config.get(:queues, ["default"]))
    Enum.map(queue_configs, fn queue_config ->
      case queue_config do
        {queue, _concurrency} -> queue
        queue -> queue
      end
    end)
  end

  defp get_concurrency(opts) do
    queue_configs = Keyword.get(opts, :queues, Config.get(:queues, ["default"]))
    per_queue_concurrency = Keyword.get(opts, :concurrency, Config.get(:concurrency, 10_000))
    Enum.map(queue_configs, fn (queue_config) ->
        case queue_config do
          {queue, concurrency} -> {queue, concurrency, 0}
          queue -> {queue, per_queue_concurrency, 0}
        end
    end)
  end

end
