defmodule Exq.Manager.Server do
  @moduledoc """
  The Manager module is the main orchestrator for the system.

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
    * `:shutdown_timeout` - The number of milliseconds to wait for workers to finish processing jobs
      when the application is shutting down

  ## Redis Options (TODO - move to supervisor after refactor):
    * `:host` - Host name for Redis server (defaults to '127.0.0.1')
    * `:port` - Redis port (defaults to 6379)
    * `:database` - Redis Database number (used for isolation. Defaults to 0).
    * `:password` - Redis authentication password (optional, off by default).
    * `:redis_options` - Additional options provided to Redix
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

       This command atomically pops an item off the queue and stores the item in a backup queue.
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
  alias Exq.Support.Config
  alias Exq.Support.Opts
  alias Exq.Redis.JobQueue
  alias Exq.Support.Redis

  @backoff_mult 10

  defmodule State do
    defstruct redis: nil,
              stats: nil,
              enqueuer: nil,
              pid: nil,
              node_id: nil,
              namespace: nil,
              dequeuers: nil,
              queues: nil,
              poll_timeout: nil,
              scheduler_poll_timeout: nil,
              workers_sup: nil,
              middleware: nil,
              metadata: nil,
              shutdown_timeout: nil
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: server_name(opts[:name]))
  end

  def job_terminated(exq, queue, success) do
    GenServer.cast(exq, {:job_terminated, queue, success})
    :ok
  end

  def server_name(nil), do: Config.get(:name)
  def server_name(name), do: name

  ## ===========================================================
  ## gen server callbacks
  ## ===========================================================

  def init(opts) do
    # Cleanup stale stats
    GenServer.cast(self(), :cleanup_host_stats)

    # Setup dequeues
    dequeuers = add_dequeuers(%{}, opts[:concurrency])

    state = %State{
      dequeuers: dequeuers,
      redis: opts[:redis],
      stats: opts[:stats],
      workers_sup: opts[:workers_sup],
      enqueuer: opts[:enqueuer],
      middleware: opts[:middleware],
      metadata: opts[:metadata],
      node_id: Config.node_identifier().node_id(),
      namespace: opts[:namespace],
      queues: opts[:queues],
      pid: self(),
      poll_timeout: opts[:poll_timeout],
      scheduler_poll_timeout: opts[:scheduler_poll_timeout],
      shutdown_timeout: opts[:shutdown_timeout]
    }

    check_redis_connection(opts)
    {:ok, state, 0}
  end

  def handle_call(:redis, _from, state) do
    {:reply, {state.redis, state.namespace}, state, 10}
  end

  def handle_call(:subscriptions, _from, state) do
    {:reply, {:ok, state.queues}, state, 0}
  end

  def handle_call({:subscribe, queue}, _from, state) do
    updated_state = add_queue(state, queue)
    {:reply, :ok, updated_state, 0}
  end

  def handle_call({:subscribe, queue, concurrency}, _from, state) do
    updated_state = add_queue(state, queue, concurrency)
    {:reply, :ok, updated_state, 0}
  end

  def handle_call({:unsubscribe, queue}, _from, state) do
    updated_state = remove_queue(state, queue)
    {:reply, :ok, updated_state, 0}
  end

  def handle_call(:unsubscribe_all, _from, state) do
    updated_state = remove_all_queues(state)
    {:reply, :ok, updated_state, 0}
  end

  def handle_cast({:re_enqueue_backup, queue}, state) do
    Redis.rescue_timeout(fn ->
      JobQueue.re_enqueue_backup(state.redis, state.namespace, state.node_id, queue)
    end)

    {:noreply, state, 0}
  end

  @doc """
  Cleanup host stats on boot
  """
  def handle_cast(:cleanup_host_stats, state) do
    Redis.rescue_timeout(fn ->
      Exq.Stats.Server.cleanup_host_stats(state.stats, state.namespace, state.node_id)
    end)

    {:noreply, state, 0}
  end

  def handle_cast({:job_terminated, queue, success}, state) do
    dequeuers =
      if success do
        maybe_call_dequeuer(state.dequeuers, queue, :processed)
      else
        maybe_call_dequeuer(state.dequeuers, queue, :failed)
      end

    {:noreply, %{state | dequeuers: dequeuers}, 0}
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

  ## ===========================================================
  ## Internal Functions
  ## ===========================================================
  @doc """
  Dequeue jobs and dispatch to workers
  """
  def dequeue_and_dispatch(state) do
    case available_queues(state) do
      {[], state} ->
        {state, state.poll_timeout}

      {queues, state} ->
        result =
          Redis.rescue_timeout(
            fn ->
              Exq.Redis.JobQueue.dequeue(state.redis, state.namespace, state.node_id, queues)
            end,
            timeout_return_value: :timeout
          )

        case result do
          :timeout ->
            {state, state.poll_timeout}

          jobs ->
            {state, job_results} =
              Enum.reduce(jobs, {state, []}, fn potential_job, {state, results} ->
                {state, result} = dispatch_job(state, potential_job)
                {state, [result | results]}
              end)

            cond do
              Enum.any?(job_results, fn status -> elem(status, 1) == :dispatch end) ->
                {state, 0}

              Enum.any?(job_results, fn status -> elem(status, 0) == :error end) ->
                Logger.error("Redis Error #{Kernel.inspect(job_results)}}.  Backing off...")
                {state, state.poll_timeout * @backoff_mult}

              true ->
                {state, state.poll_timeout}
            end
        end
    end
  end

  @doc """
  Returns list of active queues with free workers
  """
  def available_queues(state) do
    Enum.reduce(state.queues, {[], state}, fn q, {queues, state} ->
      {available, dequeuers} =
        Map.get_and_update!(state.dequeuers, q, fn {module, state} ->
          {:ok, available, state} = module.available?(state)
          {available, {module, state}}
        end)

      state = %{state | dequeuers: dequeuers}

      if available do
        {[q | queues], state}
      else
        {queues, state}
      end
    end)
  end

  @doc """
  Dispatch job to worker if it is not empty
  Also update worker count for dispatched job
  """
  def dispatch_job(state, potential_job) do
    case potential_job do
      {:ok, {:none, _queue}} ->
        {state, {:ok, :none}}

      {:ok, {job, queue}} ->
        state = dispatch_job(state, job, queue)
        {state, {:ok, :dispatch}}

      {status, reason} ->
        {state, {:error, {status, reason}}}
    end
  end

  def dispatch_job(state, job, queue) do
    {:ok, worker} =
      Exq.Worker.Supervisor.start_child(
        state.workers_sup,
        [
          job,
          state.pid,
          queue,
          state.stats,
          state.namespace,
          state.node_id,
          state.redis,
          state.middleware,
          state.metadata
        ],
        shutdown_timeout: state.shutdown_timeout
      )

    Exq.Worker.Server.work(worker)
    %{state | dequeuers: maybe_call_dequeuer(state.dequeuers, queue, :dispatched)}
  end

  # Setup dequeuers from options / configs.

  # The following is done:
  #  * Sets up queues data structure with proper concurrency settings
  #  * Sets up :ets table for tracking workers
  #  * Re-enqueues any in progress jobs that were not finished the queues
  #  * Returns list of queues and work table
  # TODO: Refactor the way queues are setup

  defp add_dequeuers(dequeuers, specs) do
    Enum.into(specs, dequeuers, fn {queue, {module, opts}} ->
      GenServer.cast(self(), {:re_enqueue_backup, queue})
      {:ok, state} = module.init(%{queue: queue}, opts)
      {queue, {module, state}}
    end)
  end

  defp remove_dequeuers(dequeuers, queues) do
    Enum.reduce(queues, dequeuers, fn queue, dequeuers ->
      maybe_call_dequeuer(dequeuers, queue, :stop)
      |> Map.delete(queue)
    end)
  end

  defp maybe_call_dequeuer(dequeuers, queue, method) do
    if Map.has_key?(dequeuers, queue) do
      Map.update!(dequeuers, queue, fn {module, state} ->
        case apply(module, method, [state]) do
          {:ok, state} -> {module, state}
          :ok -> {module, nil}
        end
      end)
    else
      dequeuers
    end
  end

  defp add_queue(state, queue, concurrency \\ Config.get(:concurrency)) do
    queue_concurrency = {queue, Opts.cast_concurrency(concurrency)}

    %{
      state
      | queues: [queue | state.queues],
        dequeuers: add_dequeuers(state.dequeuers, [queue_concurrency])
    }
  end

  defp remove_queue(state, queue) do
    updated_queues = List.delete(state.queues, queue)
    %{state | queues: updated_queues, dequeuers: remove_dequeuers(state.dequeuers, [queue])}
  end

  defp remove_all_queues(state) do
    %{state | queues: [], dequeuers: remove_dequeuers(state.dequeuers, state.queues)}
  end

  # Check Redis connection using PING and raise exception with
  # user friendly error message if Redis is down.
  defp check_redis_connection(opts) do
    try do
      {:ok, _} = Exq.Redis.Connection.q(opts[:redis], ~w(PING))

      if Keyword.get(opts, :heartbeat_enable, false) do
        :ok =
          Exq.Redis.Heartbeat.register(
            opts[:redis],
            opts[:namespace],
            Config.node_identifier().node_id()
          )
      else
        :ok
      end
    catch
      err, reason ->
        opts = Exq.Support.Opts.redis_inspect_opts(opts)

        raise """
        \n\n\n#{String.duplicate("=", 100)}
        ERROR! Could not connect to Redis!

        Configuration passed in: #{opts}
        Error: #{inspect(err)}
        Reason: #{inspect(reason)}

        Make sure Redis is running, and your configuration matches Redis settings.
        #{String.duplicate("=", 100)}
        """
    end
  end
end
