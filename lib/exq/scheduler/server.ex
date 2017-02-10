defmodule Exq.Scheduler.Server do
  @moduledoc """
  The Scheduler is responsible for monitoring the `schedule` and `retry` queues.
  These queues use a Redis sorted set (term?) to schedule and pick off due jobs.
  Once a job is at or past it's execution date, the Scheduler moves the job into the
  live execution queue.

  Runs on a timed loop according to `scheduler_poll_timeout`.

  ## Initialization:
    * `:name` - Name of target registered process
    * `:namespace` - Redis namespace to store all data under. Defaults to "exq".
    * `:queues` - Array of currently active queues (TODO: Remove, I suspect it's not needed).
    * `:redis` - pid of Redis process.
    * `:scheduler_poll_timeout` - How often to poll Redis for scheduled / retry jobs.
  """

  require Logger
  use GenServer

  defmodule State do
    defstruct redis: nil, namespace: nil, queues: nil, scheduler_poll_timeout: nil
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: server_name(opts[:name]))
  end

  def start_timeout(pid) do
    GenServer.cast(pid, :start_timeout)
  end

  def server_name(name) do
    name = name || Exq.Support.Config.get(:name)
    "#{name}.Scheduler" |> String.to_atom
   end

##===========================================================
## gen server callbacks
##===========================================================

  def init(opts) do
    state = %State{redis: opts[:redis], namespace: opts[:namespace],
      queues: opts[:queues], scheduler_poll_timeout: opts[:scheduler_poll_timeout]}

    start_timeout(self())

    {:ok, state}
  end

  def handle_cast(:start_timeout, state) do
    handle_info(:timeout, state)
  end

  def handle_info(:timeout, state) do
    {updated_state, timeout} = dequeue(state)
    {:noreply, updated_state, timeout}
  end

##===========================================================
## Internal Functions
##===========================================================

  @doc """
  Dequeue any active jobs in the scheduled and retry queues, and enqueue them to live queue.
  """
  def dequeue(state) do
    Exq.Redis.JobQueue.scheduler_dequeue(state.redis, state.namespace)
    {state, state.scheduler_poll_timeout}
  end

end
