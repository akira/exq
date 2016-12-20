defmodule Exq.Manager.Server do
  @moduledoc """
  The Manager module is the main orchestrator for the system

  It is also the entry point Pid process used by the client to interact
  with the Exq system.

  It's responsibilities include:
    * Handle interaction with client and delegate to responsible sub-system
    * Initial Setup of Redis Connection (to be moved to supervisor?).
    * Setup and tracking of in-progress workers / jobs.
    * Poll Redis for new jobs for any queues that have available workers.
    * Handling of queue state and subscriptions (addition and removal)
    * Initial re-hydration of backup queue on system restart to handle any
      orphan jobs from last system stop.

  The Manager is a GenServer with a timed process loop.

  ## Options
    * `:concurrency` - Default max number of workers to use if not passed in for each queue.
    * `:genserver_timeout` - Timeout to use for GenServer calls.
    * `:max_retries` - Maximum number of times to retry a failed job
    * `:name` - Name of target registered process
    * `:namespace` - Redis namespace to store all data under. Defaults to "exq".
    * `:queues` - List of queues to monitor. Can be an array of queues names such as ["q1", "q2"], or
      array of tuples with queue and max number of concurrent workers: [{"q1", 1}, {"q2", 20}].
      If only an array is passed in, system will use the default `concurrency` value for each queue.
    * `:redis_timeout` - Timeout to use for Redis commands.
    * `:poll_timeout` - How often to poll Redis for jobs.
    * `:scheduler_enable` - Whether scheduler / retry process should be enabled. This defaults
      to true.  Note that is you turn this off, job retries will not be enqueued.
    * `:scheduler_poll_timeout` - How often to poll Redis for scheduled / retry jobs.

  ## Redis Options (TODO - move to supervisor after refactor):
    * `:host` - Host name for Redis server (defaults to '127.0.0.1')
    * `:port` - Redis port (defaults to 6379)
    * `:database` - Redis Database number (used for isolation. Defaults to 0).
    * `:password` - Redis authentication password (optional, off by default).
    * `:reconnect_on_sleep` - (backoff) The time (in milliseconds) to wait before trying to
      reconnect when a network error occurs.
    * TODO: What about max_reconnection_attempts

  ## Job lifecycle

  The job lifecycle starts with an enqueue of a job. This can be done either
  via Exq or another system like Sidekiq / Resque.

  Note that the JobQueue encapsulates much of this logic.

  Client (Exq) -> Manager -> Enqueuer

  Assuming Exq is used to Enqueue an immediate job, the following is the flow:

    1. Client calls Exq.enqueue(Exq, "queue_name", Worker, ["arg1", "arg2"])

    2. Manager delegates to Enqueuer

    3. Enqueuer does the following:
      * Adds the queue to the "queues" list if not already there.
      * Prepare a job struct with a generated UUID and convert to JSON.
      * Push the job into the correct queue
      * Respond to client with the generated job UUID.

  At this point the job is in the correct queue ready to be dequeued.

  Manager deq Redis -> Worker (decode & execute job) --> Manager (record)
                                                     |
                                                     --> Stats (record stats)

  The dequeueing of the job is as follows:
    1. The Manager is on a polling cycle, and the :timeout message fires.

    2. Manager tabulates a list of active queues with available workers.

    3. Uses the JobQueue module to fetch jobs. The JobQueue module does this through
       a single MULT RPOPLPUSH command issued to Redis with the targeted queue.

       This command atomicaly pops an item off the queue and stores the item in a backup queue.
       The backup queue is keyed off the queue and node id, so each node would
       have their own backup queue.

       Note that we cannot use a blocking pop since BRPOPLPUSH (unlike BRPOP) is more
       limited and can only handle a single queue target (see filed issues in Redis / Sidekiq).

    4. Once the jobs are returned to the manager, the manager goes through each job
       and creates and kicks off an ephemeral Worker process that will handle the job.
       The manager also does some tabulation to reduce the worker count for those queues.

    5. The worker parses the JSON object, and figures out the worker to call.
       It also tells Stats to record a itself in process.

    6. The worker then calls "apply" on the correct target module, and tracks the failure
       or success of the job. Once the job is finished, it tells the Manager and Stats.

    7. If the job is successful, Manager and Stats simply mark the success of the job.

       If the job fails, the Worker module uses the JobQueue module to retry the job if necessary.
       The retry is done by adding the job to a "retry" queue which is a Sorted Set in Redis.
       The job is marked with the retry count and scheduled date (using exponential backup).
       The job is then removed from the backup queue.

    8. If any jobs were fetched from Redis, the Manager will poll again immediately, otherwise
       if will use the poll_timeout for the next polling.

  ## Retry / Schedule queue

  The retry / schedule queue provides functionality for scheduled jobs. This is used both
  for the `enqueue_in` method which allows a scheduled job in the future, as well
  as retry queue, which is used to retry jobs.
  """

  require Logger
  use GenServer
  alias Exq.Enqueuer
  alias Exq.Support.Config
  alias Exq.Redis.JobQueue

  @backoff_mult 10

  defmodule State do
    defstruct redis: nil, stats: nil, enqueuer: nil, pid: nil, node_id: nil, namespace: nil, work_table: nil,
              queues: nil, poll_timeout: nil, scheduler_poll_timeout: nil, workers_sup: nil,
              middleware: nil
  end

  def start_link(opts\\[]) do
    GenServer.start_link(__MODULE__, opts, name: server_name(opts[:name]))
  end

  def job_terminated(exq, namespace, queue, job_serialized) do
    GenServer.cast(exq, {:job_terminated, namespace, queue, job_serialized})
    :ok
  end

##===========================================================
## gen server callbacks
##===========================================================

  def init(opts) do
    work_table = setup_queues(opts)

    state = %State{work_table: work_table,
                   redis: opts[:redis],
                   stats: opts[:stats],
                   workers_sup: opts[:workers_sup],
                   enqueuer: opts[:enqueuer],
                   middleware: opts[:middleware],
                   node_id:  Config.node_identifier.node_id(),
                   namespace: opts[:namespace],
                   queues: opts[:queues],
                   pid: self(),
                   poll_timeout: opts[:poll_timeout],
                   scheduler_poll_timeout: opts[:scheduler_poll_timeout]
                   }

    check_redis_connection(opts)
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

  def handle_cast({:re_enqueue_backup, queue}, state) do
    rescue_timeout(fn ->
      JobQueue.re_enqueue_backup(state.redis, state.namespace, state.node_id, queue)
    end)
    {:noreply, state, 0}
  end

  def handle_cast({:job_terminated, _namespace, queue, _job_serialized}, state) do
    update_worker_count(state.work_table, queue, -1)
    {:noreply, state, 0}
  end

  def handle_info(:timeout, state) do
    {updated_state, timeout} = dequeue_and_dispatch(state)
    {:noreply, updated_state, timeout}
  end

  def handle_info(_info, state) do
    {:noreply, state, state.poll_timeout}
  end

  def terminate(_reason, _state) do
    :ok
  end

##===========================================================
## Internal Functions
##===========================================================
  @doc """
  Dequeue jobs and dispatch to workers
  """
  def dequeue_and_dispatch(state), do: dequeue_and_dispatch(state, available_queues(state))
  def dequeue_and_dispatch(state, []), do: {state, state.poll_timeout}
  def dequeue_and_dispatch(state, queues) do
    rescue_timeout({state, state.poll_timeout}, fn ->
      jobs = Exq.Redis.JobQueue.dequeue(state.redis, state.namespace, state.node_id, queues)

      job_results = jobs |> Enum.map(fn(potential_job) -> dispatch_job(state, potential_job) end)

      cond do
        Enum.any?(job_results, fn(status) -> elem(status, 1) == :dispatch end) ->
          {state, 0}
        Enum.any?(job_results, fn(status) -> elem(status, 0) == :error end) ->
          Logger.error("Redis Error #{Kernel.inspect(job_results)}}.  Backing off...")
          {state, state.poll_timeout * @backoff_mult}
        true ->
          {state, state.poll_timeout}
      end
    end)
  end

  @doc """
  Returns list of active queues with free workers
  """
  def available_queues(state) do
    Enum.filter(state.queues, fn(q) ->
      [{_, concurrency, worker_count}] = :ets.lookup(state.work_table, q)
      worker_count < concurrency
    end)
  end

  @doc """
  Dispatch job to worker if it is not empty
  Also update worker count for dispatched job
  """
  def dispatch_job(state, potential_job) do
    case potential_job do
      {:ok, {:none, _queue}} ->
        {:ok, :none}
      {:ok, {job, queue}} ->
        dispatch_job(state, job, queue)
        {:ok, :dispatch}
      {status, reason} ->
        {:error, {status, reason}}
    end
  end
  def dispatch_job(state, job, queue) do
    {:ok, worker} = Exq.Worker.Supervisor.start_child(
      state.workers_sup,
      [job, state.pid, queue, state.work_table,
       state.stats, state.namespace, state.node_id, state.redis, state.middleware])
    Exq.Worker.Server.work(worker)
    update_worker_count(state.work_table, queue, 1)
  end


  # Setup queues from options / configs.

  # The following is done:
  #  * Sets up queues data structure with proper concurrency settings
  #  * Sets up :ets table for tracking workers
  #  * Re-enqueues any in progress jobs that were not finished the queues
  #  * Returns list of queues and work table
  # TODO: Refactor the way queues are setup

  defp setup_queues(opts) do
    work_table = :ets.new(:work_table, [:set, :public])
    Enum.each(opts[:concurrency], fn (queue_concurrency) ->
      :ets.insert(work_table, queue_concurrency)
      GenServer.cast(self, {:re_enqueue_backup, elem(queue_concurrency, 0)})
    end)
    work_table
  end

  defp add_queue(state, queue, concurrency \\ Config.get(:concurrency)) do
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

  @doc """
  Rescue GenServer timeout.
  """
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

  # Check Redis connection using PING and raise exception with
  # user friendly error message if Redis is down.
  defp check_redis_connection(opts) do
    try do
      {:ok, _} = Exq.Redis.Connection.q(opts[:redis], ~w(PING))
    catch
      err, reason ->
        opts = Exq.Support.Opts.redis_opts(opts)
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

  defp server_name(nil), do: Config.get(:name)
  defp server_name(name), do: name

end
