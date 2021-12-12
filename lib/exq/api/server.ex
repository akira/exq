defmodule Exq.Api.Server do
  @moduledoc """
  The API deals with getting current stats for the UI / API.
  """

  alias Exq.Support.Config
  alias Exq.Redis.JobQueue
  alias Exq.Redis.JobStat

  use GenServer

  defmodule State do
    defstruct redis: nil, namespace: nil
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: server_name(opts[:name]))
  end

  ## ===========================================================
  ## GenServer callbacks
  ## ===========================================================

  def init(opts) do
    {:ok, %State{redis: opts[:redis], namespace: opts[:namespace]}}
  end

  def handle_call(:processes, _from, state) do
    processes = JobStat.processes(state.redis, state.namespace)
    {:reply, {:ok, processes}, state}
  end

  def handle_call(:busy, _from, state) do
    count = JobStat.busy(state.redis, state.namespace)
    {:reply, {:ok, count}, state}
  end

  def handle_call(:nodes, _from, state) do
    nodes = JobStat.nodes(state.redis, state.namespace)
    {:reply, {:ok, nodes}, state}
  end

  def handle_call({:stats, key}, _from, state) do
    count = JobStat.get_count(state.redis, state.namespace, key)
    {:reply, {:ok, count}, state}
  end

  def handle_call({:stats, key, dates}, _from, state) do
    counts = JobStat.get_counts(state.redis, state.namespace, Enum.map(dates, &"#{key}:#{&1}"))
    {:reply, {:ok, counts}, state}
  end

  def handle_call(:queues, _from, state) do
    queues = JobQueue.list_queues(state.redis, state.namespace)
    {:reply, {:ok, queues}, state}
  end

  def handle_call({:failed, options}, _from, state) do
    jobs = JobQueue.failed(state.redis, state.namespace, options)
    {:reply, {:ok, jobs}, state}
  end

  def handle_call({:retries, options}, _from, state) do
    jobs = JobQueue.scheduled_jobs(state.redis, state.namespace, "retry", options)
    {:reply, {:ok, jobs}, state}
  end

  def handle_call(:jobs, _from, state) do
    jobs = JobQueue.jobs(state.redis, state.namespace)
    {:reply, {:ok, jobs}, state}
  end

  def handle_call({:jobs, :scheduled, options}, _from, state) do
    jobs = JobQueue.scheduled_jobs(state.redis, state.namespace, "schedule", options)
    {:reply, {:ok, jobs}, state}
  end

  def handle_call({:jobs, :scheduled_with_scores}, _from, state) do
    jobs = JobQueue.scheduled_jobs_with_scores(state.redis, state.namespace, "schedule")
    {:reply, {:ok, jobs}, state}
  end

  def handle_call({:jobs, queue, options}, _from, state) do
    jobs = JobQueue.jobs(state.redis, state.namespace, queue, options)
    {:reply, {:ok, jobs}, state}
  end

  def handle_call(:queue_size, _from, state) do
    sizes = JobQueue.queue_size(state.redis, state.namespace)
    {:reply, {:ok, sizes}, state}
  end

  def handle_call({:queue_size, queue}, _from, state) do
    size = JobQueue.queue_size(state.redis, state.namespace, queue)
    {:reply, {:ok, size}, state}
  end

  def handle_call(:scheduled_size, _from, state) do
    size = JobQueue.scheduled_size(state.redis, state.namespace)
    {:reply, {:ok, size}, state}
  end

  def handle_call(:retry_size, _from, state) do
    size = JobQueue.retry_size(state.redis, state.namespace)
    {:reply, {:ok, size}, state}
  end

  def handle_call(:failed_size, _from, state) do
    size = JobQueue.failed_size(state.redis, state.namespace)
    {:reply, {:ok, size}, state}
  end

  def handle_call({:find_failed, jid}, _from, state) do
    {:ok, job} = JobStat.find_failed(state.redis, state.namespace, jid)
    {:reply, {:ok, job}, state}
  end

  def handle_call({:find_failed, score, jid, options}, _from, state) do
    {:ok, job} = JobStat.find_failed(state.redis, state.namespace, score, jid, options)
    {:reply, {:ok, job}, state}
  end

  def handle_call({:find_job, queue, jid}, _from, state) do
    response = JobQueue.find_job(state.redis, state.namespace, jid, queue)
    {:reply, response, state}
  end

  def handle_call({:find_scheduled, jid}, _from, state) do
    {:ok, job} = JobQueue.find_job(state.redis, state.namespace, jid, :scheduled)
    {:reply, {:ok, job}, state}
  end

  def handle_call({:find_scheduled, score, jid, options}, _from, state) do
    {:ok, job} = JobStat.find_scheduled(state.redis, state.namespace, score, jid, options)
    {:reply, {:ok, job}, state}
  end

  def handle_call({:find_retry, jid}, _from, state) do
    {:ok, job} = JobQueue.find_job(state.redis, state.namespace, jid, :retry)
    {:reply, {:ok, job}, state}
  end

  def handle_call({:find_retry, score, jid, options}, _from, state) do
    {:ok, job} = JobStat.find_retry(state.redis, state.namespace, score, jid, options)
    {:reply, {:ok, job}, state}
  end

  def handle_call({:remove_queue, queue}, _from, state) do
    JobStat.remove_queue(state.redis, state.namespace, queue)
    {:reply, :ok, state}
  end

  def handle_call({:remove_job, queue, jid}, _from, state) do
    JobQueue.remove_job(state.redis, state.namespace, queue, jid)
    {:reply, :ok, state}
  end

  def handle_call({:remove_enqueued_jobs, queue, raw_jobs}, _from, state) do
    JobQueue.remove_enqueued_jobs(state.redis, state.namespace, queue, raw_jobs)
    {:reply, :ok, state}
  end

  def handle_call({:remove_retry, jid}, _from, state) do
    JobQueue.remove_retry(state.redis, state.namespace, jid)
    {:reply, :ok, state}
  end

  def handle_call({:remove_retry_jobs, raw_jobs}, _from, state) do
    JobQueue.remove_retry_jobs(state.redis, state.namespace, raw_jobs)
    {:reply, :ok, state}
  end

  def handle_call({:dequeue_retry_jobs, raw_jobs}, _from, state) do
    result = JobQueue.dequeue_retry_jobs(state.redis, state.namespace, raw_jobs)
    {:reply, result, state}
  end

  def handle_call({:remove_scheduled, jid}, _from, state) do
    JobQueue.remove_scheduled(state.redis, state.namespace, jid)
    {:reply, :ok, state}
  end

  def handle_call({:remove_scheduled_jobs, raw_jobs}, _from, state) do
    JobQueue.remove_scheduled_jobs(state.redis, state.namespace, raw_jobs)
    {:reply, :ok, state}
  end

  def handle_call({:dequeue_scheduled_jobs, raw_jobs}, _from, state) do
    result = JobQueue.dequeue_scheduled_jobs(state.redis, state.namespace, raw_jobs)
    {:reply, result, state}
  end

  def handle_call({:remove_failed, jid}, _from, state) do
    JobStat.remove_failed(state.redis, state.namespace, jid)
    {:reply, :ok, state}
  end

  def handle_call({:remove_failed_jobs, raw_jobs}, _from, state) do
    JobQueue.remove_failed_jobs(state.redis, state.namespace, raw_jobs)
    {:reply, :ok, state}
  end

  def handle_call(:clear_failed, _from, state) do
    JobStat.clear_failed(state.redis, state.namespace)
    {:reply, :ok, state}
  end

  def handle_call({:dequeue_failed_jobs, raw_jobs}, _from, state) do
    result = JobQueue.dequeue_failed_jobs(state.redis, state.namespace, raw_jobs)
    {:reply, result, state}
  end

  def handle_call(:clear_processes, _from, state) do
    JobStat.clear_processes(state.redis, state.namespace)
    {:reply, :ok, state}
  end

  def handle_call(:clear_scheduled, _from, state) do
    JobQueue.delete_queue(state.redis, state.namespace, "schedule")
    {:reply, :ok, state}
  end

  def handle_call(:clear_retries, _from, state) do
    JobQueue.delete_queue(state.redis, state.namespace, "retry")
    {:reply, :ok, state}
  end

  def handle_call(:realtime_stats, _from, state) do
    {:ok, failures, successes} = JobStat.realtime_stats(state.redis, state.namespace)
    {:reply, {:ok, failures, successes}, state}
  end

  def handle_call({:retry_job, jid}, _from, state) do
    {:ok, job} = JobQueue.find_job(state.redis, state.namespace, jid, :retry)
    JobQueue.retry_job(state.redis, state.namespace, job)
    {:reply, :ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  def server_name(name) do
    name = name || Config.get(:name)
    "#{name}.Api" |> String.to_atom()
  end
end
