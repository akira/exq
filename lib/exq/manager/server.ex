defmodule Exq.Manager.Server do
  require Logger
  use GenServer
  alias Exq.Stats.Server, as: Stats
  alias Exq.Enqueuer
  alias Exq.Support.Config

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
    :ets.update_counter(work_table, queue, {3, delta})
  end


##===========================================================
## gen server callbacks
##===========================================================

  def init([opts]) do
    {:ok, redis} = Exq.Redis.Connection.connection(opts)
    name = Keyword.get(opts, :name, @default_name)

    {queues, work_table} = setup_queues(opts)
    namespace = Keyword.get(opts, :namespace, Config.get(:namespace, "exq"))
    poll_timeout = Keyword.get(opts, :poll_timeout, Config.get(:poll_timeout, 50))
    scheduler_enable = Keyword.get(opts, :scheduler_enable, Config.get(:scheduler_enable, false))
    scheduler_poll_timeout = Keyword.get(opts, :scheduler_poll_timeout, Config.get(:scheduler_poll_timeout, 200))

    {:ok, localhost} = :inet.gethostname()

    {:ok, stats} =  GenServer.start_link(Stats, {redis}, [])

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

      Exq.Scheduler.Server.start_timeout(scheduler)
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
  
  def handle_call({:subscribe, queue}, from, state) do
    updated_state = add_queue(state, queue)
    {:reply, :ok, updated_state}
  end
  
  def handle_call({:subscribe, queue, concurrency}, from, state) do
    updated_state = add_queue(state, queue, concurrency)
    {:reply, :ok, updated_state}
  end
  
  def handle_call({:unsubscribe, queue}, from, state) do
    updated_state = remove_queue(state, queue)
    {:reply, :ok, updated_state}
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
    case Exq.Redis.JobQueue.dequeue(state.redis, state.namespace, queues) do
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
    {:ok, worker} = Exq.Worker.Server.start(job, state.pid, queue, state.work_table)
    Stats.add_process(state.stats, state.namespace, worker, state.host, job)
    Exq.Worker.Server.work(worker)
    update_worker_count(state.work_table, queue, 1)
    state
  end

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
    end)
    {queues, work_table}
  end
  
  defp add_queue(state, queue, concurrency \\ Config.get(:concurrency, 10_000)) do
    queue_concurrency = {queue, concurrency, 0}
    :ets.insert(state.work_table, queue_concurrency)
    updated_queues = [queue | state.queues]
    %{state | queues: updated_queues}
  end
  
  defp remove_queue(state, queue) do
    :ets.delete(state.work_table, queue)
    updated_queues = List.delete(state.queues, queue)
    %{state | queues: updated_queues}
  end

  def default_name, do: @default_name

  def stop(_pid) do
  end
end
