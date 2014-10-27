defmodule Exq.Manager do
  require Logger
  use GenServer

  defmodule State do
    defstruct redis: nil, busy_workers: nil, namespace: nil, queues: nil, poll_timeout: nil
  end


##===========================================================
## gen server callbacks
##===========================================================

  def init(opts) do
    host = Keyword.get(opts, :host, '127.0.0.1')
    port = Keyword.get(opts, :port, 6379)
    database = Keyword.get(opts, :database, 0)
    password = Keyword.get(opts, :password, '')
    queues = Keyword.get(opts, :queues, ["default"])
    namespace = Keyword.get(opts, :namespace, "resque")
    reconnect_on_sleep = Keyword.get(opts, :reconnect_on_sleep, 100)
    poll_timeout = Keyword.get(opts, :poll_timeout, 50)
    {:ok, redis} = :eredis.start_link(host, port, database, password, reconnect_on_sleep)
    state = %State{redis: redis,
                      busy_workers: [],
                      namespace: namespace,
                      queues: queues,
                      poll_timeout: poll_timeout}
    {:ok, state, 0}
  end

  def handle_call({:enqueue, queue, worker, args}, _from, state) do
    jid = Exq.RedisQueue.enqueue(state.redis, state.namespace, queue, worker, args)
    {:reply, {:ok, jid}, state, 0}
  end

  def handle_call({:stop}, _from, state) do
    { :stop, :normal, :ok, state }
  end

  def handle_info(:timeout, state) do
    {updated_state, timeout} = dequeue_and_dispatch(state)
    {:noreply, updated_state, timeout}
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  def handle_call(_request, _from, state) do
    Logger.error("UKNOWN CALL")
    {:reply, :unknown, state, 0}
  end

  def handle_cast(_request, state) do
    Logger.error("UKNOWN CAST")
    {:noreply, state, 0}
  end

##===========================================================
## Internal Functions
##===========================================================

  def dequeue_and_dispatch(state) do
    case dequeue(state.redis, state.namespace, state.queues) do
      :none -> {state, state.poll_timeout}
      job -> {dispatch_job(state, job), 0}
    end
  end

  def dequeue(redis, namespace, queues) do
    Exq.RedisQueue.dequeue(redis, namespace, queues)
  end

  def dispatch_job(state, job) do
    {:ok, worker} = Exq.Worker.start(job)
    Exq.Worker.work(worker)
    state
  end

  def stop(pid) do
  end
end
