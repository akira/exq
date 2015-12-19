defmodule Exq.Manager.Server do
  require Logger
  use GenServer
  alias Exq.Stats.Server, as: Stats
  alias Exq.Enqueuer
  alias Exq.Redis.JobQueue
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
    scheduler_enable = Keyword.get(opts, :scheduler_enable, Config.get(:scheduler_enable, true))
    scheduler_poll_timeout = Keyword.get(opts, :scheduler_poll_timeout, Config.get(:scheduler_poll_timeout, 200))

    {:ok, localhost} = :inet.gethostname()

    stats = String.to_atom("#{name}_stats")
    {:ok, _} =  Exq.Stats.Supervisor.start_link(
      redis: redis,
      name: stats)

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

  def handle_cast(_request, state) do
    Logger.error("UNKNOWN CAST")
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
    {:reply, :ok, updated_state,0}
  end

  def handle_call({:subscribe, queue, concurrency}, from, state) do
    updated_state = add_queue(state, queue, concurrency)
    {:reply, :ok, updated_state,0}
  end

  def handle_call({:unsubscribe, queue}, from, state) do
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

  def handle_info(:timeout, state) do
    {updated_state, timeout} = dequeue_and_dispatch(state)
    {:noreply, updated_state, timeout}
  end

  def handle_info(info, state) do
    Logger.error("UNKNOWN CALL #{Kernel.inspect info}")
    {:noreply, state, state.timeout}
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, state) do
    :eredis.stop(state.redis)
    :ok
  end

##===========================================================
## Internal Functions
##===========================================================

  def dequeue_and_dispatch(state), do: dequeue_and_dispatch(state, available_queues(state))
  def dequeue_and_dispatch(state, []), do: {state, state.poll_timeout}
  def dequeue_and_dispatch(state, queues) do
    try do
      jobs = Exq.Redis.JobQueue.dequeue(state.redis, state.namespace, queues)

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
    catch
      :exit, e ->
        Logger.info("Manager timeout occurred #{Kernel.inspect e}")
        {state, state.poll_timeout}
    end
  end

  def available_queues(state) do
    Enum.filter(state.queues, fn(q) ->
      [{_, concurrency, worker_count}] = :ets.lookup(state.work_table, q)
      worker_count < concurrency
    end)
  end

  def dispatch_job!(state, potential_job) do
    case potential_job do
      {:ok, {:none, queue}} ->
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
