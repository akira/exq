defmodule Exq.Stats.Server do
  @moduledoc """
  Stats process is responsible for recording all stats into Redis.

  The stats format is compatible with the Sidekiq stats format, so that
  The Sidekiq UI can be also used to view Exq status as well, and Exq
  can run side by side with Sidekiq without breaking any of it's UI.

  This includes job success/failure as well as in-progress jobs
  """
  use GenServer
  alias Exq.Redis.JobStat
  alias Exq.Support.Config
  alias Exq.Support.Process
  alias Exq.Support.Time
  alias Exq.Redis.Connection

  require Logger

  defmodule State do
    defstruct redis: nil, queue: :queue.new()
  end

  @doc """
  Add in progress worker process
  """
  def add_process(stats, namespace, worker, host, queue, job_serialized) do
    process_info = %Process{
      pid: inspect(worker),
      host: host,
      queue: queue,
      payload: Exq.Support.Config.serializer().decode_job(job_serialized),
      run_at: Time.unix_seconds()
    }

    serialized = Exq.Support.Process.encode(process_info)
    GenServer.cast(stats, {:add_process, namespace, process_info, serialized})
    {:ok, process_info}
  end

  @doc """
  Remove in progress worker process
  """
  def process_terminated(stats, namespace, process_info) do
    GenServer.cast(stats, {:process_terminated, namespace, process_info})
    :ok
  end

  @doc """
  Record job as successfully processes
  """
  def record_processed(stats, namespace, job) do
    GenServer.cast(stats, {:record_processed, namespace, job})
    :ok
  end

  @doc """
  Record job as failed
  """
  def record_failure(stats, namespace, error, job) do
    GenServer.cast(stats, {:record_failure, namespace, error, job})
    :ok
  end

  @doc """
  Cleanup stats on boot. This includes cleaning up busy workers.
  """
  def cleanup_host_stats(stats, namespace, host) do
    GenServer.call(stats, {:cleanup_host_stats, namespace, host})
    :ok
  end

  def server_name(name) do
    name = name || Exq.Support.Config.get(:name)
    "#{name}.Stats" |> String.to_atom()
  end

  def force_flush(stats) do
    GenServer.call(stats, :force_flush)
  end

  ## ===========================================================
  ## gen server callbacks
  ## ===========================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: server_name(opts[:name]))
  end

  def init(opts) do
    Elixir.Process.flag(:trap_exit, true)
    Elixir.Process.send_after(self(), :flush, Config.get(:stats_flush_interval))
    {:ok, %State{redis: opts[:redis]}}
  end

  def handle_cast(msg, state) do
    state = %{state | queue: :queue.in(msg, state.queue)}
    {:noreply, state}
  end

  def handle_call(:force_flush, _from, state) do
    queue = process_queue(state.queue, state, [])
    state = %{state | queue: queue}
    {:reply, :ok, state}
  end

  def handle_call({:cleanup_host_stats, namespace, host}, _from, state) do
    try do
      JobStat.cleanup_processes(state.redis, namespace, host)
    rescue
      e -> Logger.error("Error cleaning up processes -  #{Kernel.inspect(e)}")
    end

    {:reply, :ok, state}
  end

  def handle_info(:flush, state) do
    queue = process_queue(state.queue, state, [])
    state = %{state | queue: queue}
    Elixir.Process.send_after(self(), :flush, Config.get(:stats_flush_interval))
    {:noreply, state}
  end

  def terminate(_reason, state) do
    # flush any pending stats
    process_queue(state.queue, state, [])
    :ok
  end

  ## ===========================================================
  ## Methods
  ## ===========================================================
  def process_queue(queue, state, redis_batch, size \\ 0) do
    case :queue.out(queue) do
      {:empty, q} ->
        if size > 0 do
          Connection.qp!(state.redis, redis_batch)
        end

        q

      {{:value, msg}, q} ->
        if size < Config.get(:stats_batch_size) do
          redis_batch = redis_batch ++ generate_instructions(msg)
          process_queue(q, state, redis_batch, size + 1)
        else
          Connection.qp!(state.redis, redis_batch)
          redis_batch = [] ++ generate_instructions(msg)
          process_queue(q, state, redis_batch, 1)
        end
    end
  end

  def generate_instructions({:add_process, namespace, process_info, serialized}) do
    JobStat.add_process_commands(namespace, process_info, serialized)
  end

  def generate_instructions({:record_processed, namespace, job}) do
    JobStat.record_processed_commands(namespace, job)
  end

  def generate_instructions({:record_failure, namespace, error, job}) do
    JobStat.record_failure_commands(namespace, error, job)
  end

  def generate_instructions({:process_terminated, namespace, process}) do
    JobStat.remove_process_commands(namespace, process)
  end
end
