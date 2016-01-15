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
  alias Exq.Support.Config

  defmodule State do
    defstruct redis: nil, namespace: nil, queues: nil, scheduler_poll_timeout: nil
  end

  def start(opts \\ []) do
    GenServer.start(__MODULE__, opts)
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, [{:name, opts[:name]|| __MODULE__}])
  end

  def start_timeout(pid) do
    GenServer.cast(pid, :start_timeout)
  end

  def server_name(nil), do: Exq.Scheduler.Server
  def server_name(name), do: "#{name}.Scheduler.Server" |> String.to_atom

##===========================================================
## gen server callbacks
##===========================================================

  def init(opts) do
    namespace = Keyword.get(opts, :namespace, Config.get(:namespace, "exq"))
    queues = Keyword.get(opts, :queues)
    scheduler_poll_timeout = Keyword.get(opts, :scheduler_poll_timeout, Config.get(:scheduler_poll_timeout, 200))
    redis = opts[:redis]
    case Process.whereis(redis) do
      nil -> Exq.Redis.Supervisor.start_link(opts)
      _ -> :ok
    end
    state = %State{redis: redis, namespace: namespace,
      queues: queues, scheduler_poll_timeout: scheduler_poll_timeout}

    start_timeout(self)

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
