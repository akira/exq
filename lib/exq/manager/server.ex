defmodule Exq.Manager.Server do
  require Logger
  use GenServer
  alias Exq.Enqueuer
  alias Exq.Support.Config
  alias Exq.Redis.JobQueue

  defmodule State do
    defstruct redis: nil, stats: nil, enqueuer: nil, pid: nil, host: nil, namespace: nil, work_table: nil,
              queues: nil, poll_timeout: nil, scheduler_poll_timeout: nil
  end

  def start_link(opts\\[]) do
    GenServer.start_link(__MODULE__, [opts], [{:name, Exq.Manager.Supervisor.server_name(opts[:name])}])
  end

  def job_terminated(exq, namespace, queue, job_json) do
    GenServer.cast(exq, {:job_terminated, namespace, queue, job_json})
    :ok
  end

##===========================================================
## gen server callbacks
##===========================================================

  def init([opts]) do
    {:ok, localhost} = :inet.gethostname()

    {queues, work_table} = setup_queues(opts)
    namespace = Keyword.get(opts, :namespace, Config.get(:namespace, "exq"))
    poll_timeout = Keyword.get(opts, :poll_timeout, Config.get(:poll_timeout, 50))
    scheduler_enable = Keyword.get(opts, :scheduler_enable, Config.get(:scheduler_enable, true))
    scheduler_poll_timeout = Keyword.get(opts, :scheduler_poll_timeout, Config.get(:scheduler_poll_timeout, 200))

    {:ok, _} = Exq.Redis.Supervisor.start_link(opts)
    redis = Exq.Redis.Supervisor.client_name(opts[:name])

    {:ok, _} =  Exq.Stats.Supervisor.start_link([{:redis, redis}|opts])

    enqueuer_name = Exq.Enqueuer.Supervisor.server_name(opts[:name], :start_by_manager)
    {:ok, _} =  Exq.Enqueuer.Supervisor.start_link(namespace: namespace,
      name: enqueuer_name,
      redis: redis)

    if scheduler_enable do
      {:ok, _scheduler_sup_pid} =  Exq.Scheduler.Supervisor.start_link(
        redis: redis,
        name: opts[:name],
        namespace: namespace,
        queues: queues,
        scheduler_poll_timeout: scheduler_poll_timeout)

      opts[:name]
        |> Exq.Scheduler.Supervisor.server_name
        |> Exq.Scheduler.Server.start_timeout
    end

    state = %State{work_table: work_table,
                   redis: redis,
                   stats: Exq.Stats.Supervisor.server_name(opts[:name]),
                   enqueuer: enqueuer_name,
                   host:  to_string(localhost),
                   namespace: namespace,
                   queues: queues,
                   pid: self(),
                   poll_timeout: poll_timeout,
                   scheduler_poll_timeout: scheduler_poll_timeout
                   }

    check_redis_connection(redis, opts)
    {:ok, state, 0}
  end

  def handle_call({:enqueue, queue, worker, args}, from, state) do
    Enqueuer.enqueue(state.enqueuer, from, queue, worker, args)
    {:noreply, state, 10}
  end

  def handle_call({:enqueue_at, queue, time, worker, args}, from, state) do
    Enqueuer.enqueue_at(state.enqueuer, from, queue, time, worker, args)
    {:noreply, state, 10}
  end

  def handle_call({:enqueue_in, queue, offset, worker, args}, from, state) do
    Enqueuer.enqueue_in(state.enqueuer, from, queue, offset, worker, args)
    {:noreply, state, 10}
  end

  def handle_call({:subscribe, queue}, _from, state) do
    updated_state = add_queue(state, queue)
    {:reply, :ok, updated_state,0}
  end

  def handle_call({:subscribe, queue, concurrency}, _from, state) do
    updated_state = add_queue(state, queue, concurrency)
    {:reply, :ok, updated_state,0}
  end

  def handle_call({:unsubscribe, queue}, _from, state) do
    updated_state = remove_queue(state, queue)
    {:reply, :ok, updated_state,0}
  end

  def handle_call({:stop}, _from, state) do
    { :stop, :normal, :ok, state }
  end

  def handle_call(_request, _from, state) do
    Logger.error("UNKNOWN CALL")
    {:reply, :unknown, state, 0}
  end

  def handle_cast({:re_enqueue_backup, queue}, state) do
    rescue_timeout(fn ->
      JobQueue.re_enqueue_backup(state.redis, state.namespace, state.host, queue)
    end)
    {:noreply, state, 0}
  end

  def handle_cast({:job_terminated, _namespace, queue, job_json}, state) do
    rescue_timeout(fn ->
      update_worker_count(state.work_table, queue, -1)
      JobQueue.remove_job_from_backup(state.redis, state.namespace, state.host, queue, job_json)
    end)
    {:noreply, state, 0}
  end

  def handle_cast(_request, state) do
    Logger.error("UNKNOWN CAST")
    {:noreply, state, 0}
  end

  def handle_info(:timeout, state) do
    {updated_state, timeout} = dequeue_and_dispatch(state)
    {:noreply, updated_state, timeout}
  end

  def handle_info(info, state) do
    Logger.error("UNKNOWN CALL #{Kernel.inspect info}")
    {:noreply, state, state.poll_timeout}
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, state) do
    case Process.whereis(state.redis) do
      nil -> :ignore
      pid -> Redix.stop(pid)
    end
    :ok
  end

##===========================================================
## Internal Functions
##===========================================================

  def dequeue_and_dispatch(state), do: dequeue_and_dispatch(state, available_queues(state))
  def dequeue_and_dispatch(state, []), do: {state, state.poll_timeout}
  def dequeue_and_dispatch(state, queues) do
    rescue_timeout({state, state.poll_timeout}, fn ->
      jobs = Exq.Redis.JobQueue.dequeue(state.redis, state.namespace, state.host, queues)

      job_results = jobs |> Enum.map(fn(potential_job) -> dispatch_job!(state, potential_job) end)

      cond do
        Enum.any?(job_results, fn(status) -> elem(status, 1) == :dispatch end) ->
          {state, 0}
        Enum.any?(job_results, fn(status) -> elem(status, 0) == :error end) ->
          Logger.error("Redis Error #{Kernel.inspect(job_results)}}.  Backing off...")
          {state, state.poll_timeout * 10}
        true ->
          {state, state.poll_timeout}
      end
    end)
  end

  def available_queues(state) do
    Enum.filter(state.queues, fn(q) ->
      [{_, concurrency, worker_count}] = :ets.lookup(state.work_table, q)
      worker_count < concurrency
    end)
  end

  def dispatch_job!(state, potential_job) do
    case potential_job do
      {:ok, {:none, _queue}} ->
        {:ok, :none}
      {:ok, {job, queue}} ->
        dispatch_job!(state, job, queue)
        {:ok, :dispatch}
      {status, reason} ->
        {:error, {status, reason}}
    end
  end
  def dispatch_job!(state, job, queue) do
    {:ok, worker} = Exq.Worker.Server.start(
      job, state.pid, queue, state.work_table,
      state.stats, state.namespace, state.host)
    Exq.Worker.Server.work(worker)
    update_worker_count(state.work_table, queue, 1)
  end

  # TODO: Refactor the way queues are setup
  defp setup_queues(opts) do
    queue_configs = Keyword.get(opts, :queues, Config.get(:queues, ["default"]))
    queues = Enum.map(queue_configs, fn queue_config ->
      case queue_config do
        {queue, _concurrency} -> queue
        queue -> queue
      end
    end)
    work_table = :ets.new(:work_table, [:set, :public])
    per_queue_concurrency = Keyword.get(opts, :concurrency, Config.get(:concurrency, 10_000))
    Enum.each(queue_configs, fn (queue_config) ->
      queue_concurrency = case queue_config do
        {queue, concurrency} -> {queue, concurrency, 0}
        queue -> {queue, per_queue_concurrency, 0}
      end
      :ets.insert(work_table, queue_concurrency)
      GenServer.cast(self, {:re_enqueue_backup, elem(queue_concurrency, 0)})
    end)
    {queues, work_table}
  end

  defp add_queue(state, queue, concurrency \\ Config.get(:concurrency, 10_000)) do
    queue_concurrency = {queue, concurrency, 0}
    :ets.insert(state.work_table, queue_concurrency)
    GenServer.cast(self, {:re_enqueue_backup, queue})
    updated_queues = [queue | state.queues]
    %{state | queues: updated_queues}
  end

  defp remove_queue(state, queue) do
    :ets.delete(state.work_table, queue)
    updated_queues = List.delete(state.queues, queue)
    %{state | queues: updated_queues}
  end

  def update_worker_count(work_table, queue, delta) do
    :ets.update_counter(work_table, queue, {3, delta})
  end

  def rescue_timeout(f) do
    rescue_timeout(nil, f)
  end
  def rescue_timeout(fail_return, f) do
    try do
      f.()
    catch
      :exit, {:timeout, info} ->
        Logger.info("Manager timeout occurred #{Kernel.inspect info}")
        fail_return
    end
  end

  defp check_redis_connection(redis, opts) do
    try do
      {:ok, _} = Exq.Redis.Connection.q(redis, ~w(PING))
    catch
      err, reason ->
        opts = Exq.Redis.Supervisor.info(opts)
        raise """
        \n\n\n#{String.duplicate("=", 100)}
        ERROR! Could not connect to Redis!

        Configuration passed in: #{inspect opts}
        Error: #{inspect err}
        Reason: #{inspect reason}

        Make sure Redis is running, and your configuration matches Redis settings.
        #{String.duplicate("=", 100)}
        """
    end
  end

end
