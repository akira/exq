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

  def server_name(name) do
    unless name, do: name = Exq.Support.Config.get(:name, Exq)
    "#{name}.Stats" |> String.to_atom
  end

##===========================================================
## gen server callbacks
##===========================================================

  def start_link(opts \\[]) do
    GenServer.start_link(__MODULE__, opts, name: server_name(opts[:name]))
  end

  # These are the callbacks that GenServer.Behaviour will use
  def init(opts) do
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

##===========================================================
## Methods
##===========================================================

end
