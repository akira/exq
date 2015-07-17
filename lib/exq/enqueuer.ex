defmodule Exq.Enqueuer do
  require Logger
  use GenServer

  @default_name :exq_enqueuer

  defmodule State do
    defstruct redis: nil, namespace: nil, redis_owner: false
  end

  def start(opts \\ []) do
    GenServer.start(__MODULE__, [opts])
  end

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    GenServer.start_link(__MODULE__, [opts], [{:name, name}])
  end

  def enqueue(pid, queue, worker, args) do
    GenServer.call(pid, {:enqueue, queue, worker, args})
  end

  # Sync call, replies to "from" sender
  def enqueue(pid, from, queue, worker, args) do
    GenServer.cast(pid, {:enqueue, from, queue, worker, args})
  end


  def queues(pid) do
    GenServer.call(pid, {:queues})
  end

  def busy(pid) do
    GenServer.call(pid, {:busy})
  end 

  def stats(pid, key) do
    GenServer.call(pid, {:stats, key})
  end 

  def stats(pid, key, date) do
    GenServer.call(pid, {:stats, key, date})
  end

  def processes(pid) do
    GenServer.call(pid, {:processes})
  end

  def jobs(pid) do
    GenServer.call(pid, {:jobs})
  end

  def jobs(pid, queue) do
    GenServer.call(pid, {:jobs, queue})
  end

  def queue_size(pid) do
    GenServer.call(pid, {:queue_size})
  end

  def queue_size(pid, queue) do
    GenServer.call(pid, {:queue_size, queue})
  end

  def find_failed(pid, jid) do
    GenServer.call(pid, {:find_failed, jid})
  end

  def find_job(pid, queue, jid) do
    GenServer.call(pid, {:find_job, queue, jid})
  end



  def stop(pid) do
    GenServer.call(pid, {:stop})
  end

  def default_name, do: @default_name

##===========================================================
## gen server callbacks
##===========================================================

  def init([opts]) do
    namespace = Keyword.get(opts, :namespace, Exq.Config.get(:namespace, "exq"))
    redis = case Keyword.get(opts, :redis) do
      nil ->
        {:ok, r} = Exq.Redis.connection(opts)
        r
      r -> r
    end
    state = %State{redis: redis, redis_owner: true, namespace: namespace}
    {:ok, state}
  end

  def handle_call({:stop}, _from, state) do
    { :stop, :normal, :ok, state }
  end

  def handle_call({:enqueue, queue, worker, args}, _from, state) do
    jid = Exq.RedisQueue.enqueue(state.redis, state.namespace, queue, worker, args)
    {:reply, {:ok, jid}, state}
  end

  def handle_cast({:enqueue, from, queue, worker, args}, state) do
    jid = Exq.RedisQueue.enqueue(state.redis, state.namespace, queue, worker, args)
    GenServer.reply(from, {:ok, jid})
    {:noreply, state}
  end

  # WebUI Stats callbacks

  def handle_call({:processes}, _from, state) do
    processes = Exq.Stats.processes(state.redis, state.namespace)
    {:reply, {:ok, processes}, state, 0}
  end

  def handle_call({:busy}, _from, state) do
    count = Exq.Stats.busy(state.redis, state.namespace)
    {:reply, {:ok, count}, state, 0}
  end

  def handle_call({:stats, key}, _from, state) do
    count = Exq.Stats.get(state.redis, state.namespace, key)
    {:reply, {:ok, count}, state, 0}
  end

  def handle_call({:stats, key, date}, _from, state) do
    count = Exq.Stats.get(state.redis, state.namespace, "#{key}:#{date}")
    {:reply, {:ok, count}, state, 0}
  end

  def handle_call({:queues}, _from, state) do
    queues = list_queues(state.redis, state.namespace)
    {:reply, {:ok, queues}, state, 0}
  end

  def handle_call({:failed}, _from, state) do
   jobs = list_failed(state.redis, state.namespace)
   {:reply, {:ok, jobs}, state, 0}
  end


  def handle_call({:jobs}, _from, state) do
    queues = list_queues(state.redis, state.namespace)
    jobs = for q <- queues, do: {q, list_jobs(state.redis, state.namespace, q)}
    {:reply, {:ok, jobs}, state, 0}
  end

  def handle_call({:jobs, queue}, _from, state) do
    jobs = list_jobs(state.redis, state.namespace, queue)
    {:reply, {:ok, jobs}, state, 0}
  end

  def handle_call({:queue_size}, _from, state) do
    queues = list_queues(state.redis, state.namespace)
    sizes = for q <- queues, do: {q, queue_size(state.redis, state.namespace, q)}
    {:reply, {:ok, sizes}, state, 0}
  end

  def handle_call({:queue_size, queue}, _from, state) do
    size = queue_size(state.redis, state.namespace, queue)
    {:reply, {:ok, size}, state, 0}
  end

  def handle_call({:find_failed, jid}, _from, state) do
    {:ok, job, idx} = Exq.Stats.find_failed(state.redis, state.namespace, jid)
    {:reply, {:ok, job, idx}, state, 0}
  end

  def handle_call({:find_job, queue, jid}, _from, state) do
    {:ok, job, idx} = Exq.RedisQueue.find_job(state.redis, state.namespace, jid, queue)
    {:reply, {:ok, job, idx}, state, 0}
  end

  def handle_call({:remove_queue, queue}, _from, state) do
    Exq.Stats.remove_queue(state.redis, state.namespace, queue)
    {:reply, {:ok}, state, 0}
  end

  def handle_call({:remove_failed, jid}, _from, state) do
    Exq.Stats.remove_failed(state.redis, state.namespace, jid)
    {:reply, {:ok}, state, 0}
  end

  def handle_call({:clear_failed}, _from, state) do
    Exq.Stats.clear_failed(state.redis, state.namespace)
    {:reply, {:ok}, state, 0}
  end

  def handle_call({:clear_processes}, _from, state) do
    Exq.Stats.clear_processes(state.redis, state.namespace)
    {:reply, {:ok}, state, 0}
  end

  def handle_call({:realtime_stats}, _from, state) do
    {:ok, failures, successes} = Exq.Stats.realtime_stats(state.redis, state.namespace)
    {:reply, {:ok, failures, successes}, state, 0}
  end
  
  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, state) do
    if state.redis_owner do
      :eredis.stop(state.redis)
    end
    :ok
  end

  # Internal Functions

  def list_queues(redis, namespace) do
    Exq.Redis.smembers!(redis, "#{namespace}:queues")
  end

  def list_jobs(redis, namespace, queue) do
    Exq.Redis.lrange!(redis, "#{namespace}:queue:#{queue}")
  end

  def list_failed(redis, namespace) do
    Exq.Redis.smembers!(redis, "#{namespace}:failed")
  end

  def queue_size(redis, namespace, queue) do
    Exq.Redis.llen!(redis, "#{namespace}:queue:#{queue}")
  end


end