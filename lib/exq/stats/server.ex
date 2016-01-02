defmodule Exq.Stats.Server do
  @moduledoc """
  Stats process is responsible for recording all stats into Redis.

  The stats format is compatible with the Sidekiq stats format, so that
  The Sidekiq UI can be also used to view Exq status as well, and Exq
  can run side by side with Sidekiq without breaking any of it's UI.

  This includes job success/failure as well as in-progress jobs
  """
  use GenServer
  use Timex
  alias Exq.Redis.JobStat
  alias Exq.Support.Process
  require Logger

  defmodule State do
    defstruct redis: nil
  end

  @doc """
  Add in progress worker process
  """
  def add_process(stats, namespace, worker, host, job) do
    process_info = %Process{pid: worker, host: host, job: job, started_at: DateFormat.format!(Date.universal, "{ISO}")}
    GenServer.cast(stats, {:add_process, namespace, process_info})
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

##===========================================================
## gen server callbacks
##===========================================================

  def start_link(opts \\[]) do
    GenServer.start_link(__MODULE__, [opts], name: opts[:name] || __MODULE__)
  end

  # These are the callbacks that GenServer.Behaviour will use
  def init([opts]) do
    {:ok, %State{redis: opts[:redis]}}
  end

  def handle_cast({:add_process, namespace, process_info}, state) do
    JobStat.add_process(state.redis, namespace, process_info)
    {:noreply, state}
  end

  def handle_cast({:record_processed, namespace, job}, state) do
    JobStat.record_processed(state.redis, namespace, job)
    {:noreply, state}
  end

  def handle_cast({:record_failure, namespace, error, job}, state) do
    JobStat.record_failure(state.redis, namespace, error, job)
    {:noreply, state}
  end

  def handle_cast({:process_terminated, namespace, process}, state) do
    :ok = JobStat.remove_process(state.redis, namespace, process)
    {:noreply, state}
  end

  def handle_cast(data, state) do
    Logger.error("INVALID MESSAGE #{Kernel.inspect data}")
    {:noreply, state}
  end

  def handle_call(:stop, _from, state) do
    { :stop, :normal, :ok, state }
  end

  def handle_info(info, state) do
    Logger.error("INVALID MESSAGE #{info}")
    {:noreply, state}
  end

  def terminate(_reason, _state) do
    {:ok}
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

##===========================================================
## Methods
##===========================================================

end
