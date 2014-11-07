defmodule Exq.Enqueuer do
  require Logger
  use GenServer

  @default_name :exq_enqueuer

  defmodule State do
    defstruct redis: nil, namespace: nil, redis_owner: false
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

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

  def terminate(_reason, state) do
    if state.redis_owner do
      :eredis.stop(state.redis)
    end
    :ok
  end
end