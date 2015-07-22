defmodule Exq.Manager do
  require Logger
  use GenServer
  use Timex

  @default_name :exq

  defmodule State do
    defstruct pid: nil, host: nil, redis: nil, namespace: nil, work_table: nil,
              queues: nil, poll_timeout: nil, stats: nil, enqueuer: nil, scheduler: nil,
              scheduler_poll_timeout: nil
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, [opts], [{:name, name}])
  end

  def update_worker_count(work_table, queue, delta) do
    [{_, concurrency, worker_count}] = :ets.lookup(work_table, queue)
    :ets.insert(work_table, {queue, concurrency, worker_count + delta})
  end


##===========================================================
## gen server callbacks
##===========================================================

  def init([opts]) do
    {:ok, redis} = Exq.Redis.connection(opts)
    name = Keyword.get(opts, :name, @default_name)

    {queues, work_table} = setup_queues(opts)
    namespace = Keyword.get(opts, :namespace, Exq.Config.get(:namespace, "exq"))
    poll_timeout = Keyword.get(opts, :poll_timeout, Exq.Config.get(:poll_timeout, 50))
    scheduler_enable = Keyword.get(opts, :scheduler_enable, Exq.Config.get(:scheduler_enable, false))
    scheduler_poll_timeout = Keyword.get(opts, :scheduler_poll_timeout, Exq.Config.get(:scheduler_poll_timeout, 200))

    {:ok, localhost} = :inet.gethostname()

    {:ok, stats} =  GenServer.start_link(Exq.Stats, {redis}, [])

    enqueuer = String.to_atom("#{name}_enqueuer")
    {:ok, _} =  Exq.Enqueuer.Supervisor.start_link(
      redis: redis,
      name: enqueuer,
      namespace: namespace)

    scheduler = String.to_atom("#{name}_scheduler")

    if scheduler_enable do
      {:ok, _} =  Exq.Scheduler.Supervisor.start_link(
        redis: redis,
        name: scheduler,
        namespace: namespace,
        queues: queues,
        scheduler_poll_timeout: scheduler_poll_timeout)

      Exq.Scheduler.start_timeout(scheduler)
    end

    state = %State{redis: redis,
                      work_table: work_table,
                      enqueuer: enqueuer,
                      scheduler: scheduler,
                      host:  to_string(localhost),
                      namespace: namespace,
                      queues: queues,
                      pid: self(),
                      poll_timeout: poll_timeout,
                      scheduler_poll_timeout: scheduler_poll_timeout,
                      stats: stats}

    {:ok, state, 0}
  end

  def handle_cast({:worker_terminated, pid}, state) do
    GenServer.cast(state.stats, {:process_terminated, state.namespace, state.host, pid})
    {:noreply, state, 0}
  end

  def handle_cast({:success, job}, state) do
    GenServer.cast(state.stats, {:record_processed, state.namespace, job})
    {:noreply, state, 0}
  end

  def handle_cast({:failure, error, job}, state) do
    GenServer.cast(state.stats, {:record_failure, state.namespace, error, job})
    {:noreply, state, 0}
  end

  def handle_cast(_request, state) do
    Logger.error("UKNOWN CAST")
    {:noreply, state, 0}
  end

  def handle_call({:enqueue, queue, worker, args}, from, state) do
    Exq.Enqueuer.enqueue(state.enqueuer, from, queue, worker, args)
    {:noreply, state, 10}
  end

  def handle_call({:enqueue_at, queue, time, worker, args}, from, state) do
    Exq.Enqueuer.enqueue_at(state.enqueuer, from, queue, time, worker, args)
    {:noreply, state, 10}
  end

  def handle_call({:enqueue_in, queue, offset, worker, args}, from, state) do
    Exq.Enqueuer.enqueue_in(state.enqueuer, from, queue, offset, worker, args)
    {:noreply, state, 10}
  end

  def handle_call({:stop}, _from, state) do
    { :stop, :normal, :ok, state }
  end

  def handle_call(_request, _from, state) do
    Logger.error("UKNOWN CALL")
    {:reply, :unknown, state, 0}
  end

  def handle_info(:timeout, state) do
    {updated_state, timeout} = dequeue_and_dispatch(state)
    {:noreply, updated_state, timeout}
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, state) do
    GenServer.call(state.stats, {:stop})
    :eredis.stop(state.redis)
    :ok
  end

##===========================================================
## Internal Functions
##===========================================================

  def dequeue_and_dispatch(state), do: dequeue_and_dispatch(state, available_queues(state))
  def dequeue_and_dispatch(state, []), do: {state, state.poll_timeout}
  def dequeue_and_dispatch(state, queues) do
    case Exq.RedisQueue.dequeue(state.redis, state.namespace, queues) do
      {:none, _}   -> {state, state.poll_timeout}
      {job, queue} -> {dispatch_job(state, job, queue), 0}
    end
  end

  def available_queues(state) do
    Enum.filter(state.queues, fn(q) ->
      [{_, concurrency, worker_count}] = :ets.lookup(state.work_table, q)
      worker_count < concurrency
    end)
  end

  def dispatch_job(state, job, queue) do
    {:ok, worker} = Exq.Worker.start(job, state.pid, queue, state.work_table)
    Exq.Stats.add_process(state.stats, state.namespace, worker, state.host, job)
    Exq.Worker.work(worker)
    update_worker_count(state.work_table, queue, 1)
    state
  end

  defp setup_queues(opts) do
    queue_configs = Keyword.get(opts, :queues, Exq.Config.get(:queues, ["default"]))
    queues = Enum.map(queue_configs, fn queue_config ->
      case queue_config do
        {queue, _concurrency} -> queue
        queue -> queue
      end
    end)
    work_table = :ets.new(:work_table, [:set, :public])
    per_queue_concurrency = Keyword.get(opts, :concurrency, Exq.Config.get(:concurrency, 10_000))
    Enum.each(queue_configs, fn (queue_config) ->
      queue_concurrency = case queue_config do
        {queue, concurrency} -> {queue, concurrency, 0}
        queue -> {queue, per_queue_concurrency, 0}
      end
      :ets.insert(work_table, queue_concurrency)
    end)
    {queues, work_table}
  end

  def default_name, do: @default_name

  def stop(_pid) do
  end
end
