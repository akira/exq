defmodule Exq.Enqueuer.Server do
  @moduledoc """
  The Enqueuer is responsible for enqueueing jobs into Redis. It can
  either be called directly by the client, or instantiated as a standalone process.

  It supports enqueuing immediate jobs, or scheduling jobs in the future.

  ## Initialization:
    * `:name` - Name of target registered process
    * `:namespace` - Redis namespace to store all data under. Defaults to "exq".
    * `:queues` - Array of currently active queues (TODO: Remove, I suspect it's not needed).
    * `:redis` - pid of Redis process.
    * `:scheduler_poll_timeout` - How often to poll Redis for scheduled / retry jobs.
  """

  require Logger

  alias Exq.Support.Config
  alias Exq.Redis.JobQueue
  use GenServer

  defmodule State do
    defstruct redis: nil, namespace: nil
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: server_name(opts[:name]))
  end

##===========================================================
## gen server callbacks
##===========================================================

  def init(opts) do
    {:ok, %State{redis: opts[:redis], namespace: opts[:namespace]}}
  end

  def handle_cast({:enqueue, from, queue, worker, args, retry}, state) do
    response = JobQueue.enqueue(state.redis, state.namespace, queue, worker, args, retry)
    GenServer.reply(from, response)
    {:noreply, state}
  end

  def handle_cast({:enqueue_at, from, queue, time, worker, args, retry}, state) do
    response = JobQueue.enqueue_at(state.redis, state.namespace, queue, time, worker, args, retry)
    GenServer.reply(from, response)
    {:noreply, state}
  end

  def handle_cast({:enqueue_in, from, queue, offset, worker, args, retry}, state) do
    response = JobQueue.enqueue_in(state.redis, state.namespace, queue, offset, worker, args, retry)
    GenServer.reply(from, response)
    {:noreply, state}
  end

  def handle_call({:enqueue, queue, worker, args, retry}, _from, state) do
    response = JobQueue.enqueue(state.redis, state.namespace, queue, worker, args, retry)
    {:reply, response, state}
  end

  def handle_call({:enqueue_at, queue, time, worker, args, retry}, _from, state) do
    response = JobQueue.enqueue_at(state.redis, state.namespace, queue, time, worker, args, retry)
    {:reply, response, state}
  end

  def handle_call({:enqueue_in, queue, offset, worker, args, retry}, _from, state) do
    response = JobQueue.enqueue_in(state.redis, state.namespace, queue, offset, worker, args, retry)
    {:reply, response, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  # Internal Functions

  def server_name(name) do
    name = name || Config.get(:name)
    "#{name}.Enqueuer" |> String.to_atom
  end
end
