defmodule Exq.Api.Server do
  @moduledoc """
  The Api deals with getting current stats for the UI / API.
  """

  alias Exq.Support.Config
  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue
  alias Exq.Redis.JobStat
  import Exq.Redis.JobQueue, only: [full_key: 2]
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

  def handle_call(:processes, _from, state) do
    processes = JobStat.processes(state.redis, state.namespace)
    {:reply, {:ok, processes}, state, 0}
  end

  def handle_call(:busy, _from, state) do
    count = JobStat.busy(state.redis, state.namespace)
    {:reply, {:ok, count}, state, 0}
  end

  def handle_call({:stats, key}, _from, state) do
    count = get_count(state, key)
    {:reply, {:ok, count}, state, 0}
  end

  def handle_call({:stats, key, date}, _from, state) do
    count = get_count(state, "#{key}:#{date}")
    {:reply, {:ok, count}, state, 0}
  end

  def handle_call(:queues, _from, state) do
    queues = list_queues(state)
    {:reply, {:ok, queues}, state, 0}
  end

  def handle_call(:failed, _from, state) do
   jobs = list_failed(state)
   {:reply, {:ok, jobs}, state, 0}
  end

  def handle_call(:retries, _from, state) do
   jobs = list_retry(state)
   {:reply, {:ok, jobs}, state, 0}
  end

  def handle_call(:jobs, _from, state) do
    queues = list_queues(state)
    jobs = for q <- queues, do: {q, list_jobs(state, q)}
    {:reply, {:ok, jobs}, state, 0}
  end
  def handle_call({:jobs, :scheduled}, _from, state) do
    jobs = list_jobs(state, :scheduled)
    {:reply, {:ok, jobs}, state, 0}
  end
  def handle_call({:jobs, queue}, _from, state) do
    jobs = list_jobs(state, queue)
    {:reply, {:ok, jobs}, state, 0}
  end

  def handle_call(:queue_size, _from, state) do
    queues = list_queues(state)
    sizes = for q <- queues, do: {q, queue_size(state, q)}
    {:reply, {:ok, sizes}, state, 0}
  end
  def handle_call({:queue_size, :scheduled}, _from, state) do
    size = queue_size(state, :scheduled)
    {:reply, {:ok, size}, state, 0}
  end
  def handle_call({:queue_size, queue}, _from, state) do
    size = queue_size(state, queue)
    {:reply, {:ok, size}, state, 0}
  end

  def handle_call({:find_failed, jid}, _from, state) do
    {:ok, job, idx} = JobStat.find_failed(state.redis, state.namespace, jid)
    {:reply, {:ok, job, idx}, state, 0}
  end

  def handle_call({:find_job, queue, jid}, _from, state) do
    {:ok, job, idx} = JobQueue.find_job(state.redis, state.namespace, jid, queue)
    {:reply, {:ok, job, idx}, state, 0}
  end

  def handle_call({:find_scheduled_job, jid}, _from, state) do
    {:ok, job, idx} = JobQueue.find_job(state.redis, state.namespace, jid, :scheduled)
    {:reply, {:ok, job, idx}, state, 0}
  end

  def handle_call({:remove_queue, queue}, _from, state) do
    JobStat.remove_queue(state.redis, state.namespace, queue)
    {:reply, {:ok}, state, 0}
  end

  def handle_call({:remove_failed, jid}, _from, state) do
    JobStat.remove_failed(state.redis, state.namespace, jid)
    {:reply, {:ok}, state, 0}
  end

  def handle_call(:clear_failed, _from, state) do
    JobStat.clear_failed(state.redis, state.namespace)
    {:reply, {:ok}, state, 0}
  end

  def handle_call(:clear_processes, _from, state) do
    JobStat.clear_processes(state.redis, state.namespace)
    {:reply, {:ok}, state, 0}
  end

  def handle_call(:clear_scheduled, _from, state) do
    delete_queue(state, "schedule")
    {:reply, {:ok}, state, 0}
  end

  def handle_call(:clear_retries, _from, state) do
    delete_queue(state, "retry")
    {:reply, {:ok}, state, 0}
  end

  def handle_call(:realtime_stats, _from, state) do
    {:ok, failures, successes} = JobStat.realtime_stats(state.redis, state.namespace)
    {:reply, {:ok, failures, successes}, state, 0}
  end

  def terminate(_reason, _state) do
    :ok
  end

  # Internal Functions
  def get_count(%State{redis: redis, namespace: namespace}, key) do
    case Connection.get!(redis, full_key(namespace, "stat:#{key}")) do
      :undefined ->
        0
      count ->
        count
    end
  end

  def list_queues(%State{redis: redis, namespace: namespace}) do
    Connection.smembers!(redis, full_key(namespace, "queues"))
  end

  def list_jobs(%State{redis: redis, namespace: namespace}, :scheduled) do
    Connection.zrangebyscorewithscore!(redis, full_key(namespace, "schedule"))
  end
  def list_jobs(%State{redis: redis, namespace: namespace}, queue) do
    Connection.lrange!(redis, full_key(namespace, "queue:#{queue}"))
  end

  def list_failed(%State{redis: redis, namespace: namespace}) do
    Connection.zrange!(redis, full_key(namespace, "dead"))
  end

  def list_retry(%State{redis: redis, namespace: namespace}) do
    Connection.zrange!(redis, full_key(namespace, "retry"))
  end

  def queue_size(%State{redis: redis, namespace: namespace}, :scheduled) do
    Connection.zcard!(redis, full_key(namespace, "schedule"))
  end
  def queue_size(%State{redis: redis, namespace: namespace}, :retry) do
    Connection.zcard!(redis, full_key(namespace, "retry"))
  end
  def queue_size(%State{redis: redis, namespace: namespace}, queue) do
    Connection.llen!(redis, full_key(namespace, "queue:#{queue}"))
  end

  def delete_queue(%State{redis: redis, namespace: namespace}, queue) do
    Connection.del!(redis, full_key(namespace, queue))
  end

  def server_name(name) do
    unless name, do: name = Config.get(:name)
    "#{name}.Api" |> String.to_atom
  end
end
