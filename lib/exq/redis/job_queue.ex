defmodule Exq.Redis.JobQueue do
  @moduledoc """
  The JobQueue module is the main abstraction of a job queue on top of Redis.

  It provides functionality for:
    * Storing jobs in Redis
    * Fetching the next job(s) to be executed (and storing a backup of these).
    * Scheduling future jobs in Redis
    * Fetching scheduling jobs and moving them to current job list
    * Retrying or failing a job
    * Re-hydrating jobs from a backup queue

  """

  require Logger

  alias Exq.Redis.Connection
  alias Exq.Redis.Script
  alias Exq.Support.Job
  alias Exq.Support.Config
  alias Exq.Support.Time

  @default_size 100

  def enqueue(redis, namespace, queue, worker, args, options) do
    {jid, job_serialized} = to_job_serialized(queue, worker, args, options)

    case enqueue(redis, namespace, queue, job_serialized) do
      :ok -> {:ok, jid}
      other -> other
    end
  end

  def enqueue(redis, namespace, job_serialized) do
    job = Config.serializer().decode_job(job_serialized)

    case enqueue(redis, namespace, job.queue, job_serialized) do
      :ok -> {:ok, job.jid}
      error -> error
    end
  end

  def enqueue(redis, namespace, queue, job_serialized) do
    try do
      response =
        Connection.qp(redis, [
          ["SADD", full_key(namespace, "queues"), queue],
          ["LPUSH", queue_key(namespace, queue), job_serialized]
        ])

      case response do
        {:ok, [%Redix.Error{}, %Redix.Error{}]} = error -> error
        {:ok, [%Redix.Error{}, _]} = error -> error
        {:ok, [_, %Redix.Error{}]} = error -> error
        {:ok, [_, _]} -> :ok
        other -> other
      end
    catch
      :exit, e ->
        Logger.info("Error enqueueing -  #{Kernel.inspect(e)}")
        {:error, :timeout}
    end
  end

  def enqueue_in(redis, namespace, queue, offset, worker, args, options)
      when is_integer(offset) do
    time = Time.offset_from_now(offset)
    enqueue_at(redis, namespace, queue, time, worker, args, options)
  end

  def enqueue_at(redis, namespace, queue, time, worker, args, options) do
    {jid, job_serialized} = to_job_serialized(queue, worker, args, options)
    enqueue_job_at(redis, namespace, job_serialized, jid, time, scheduled_queue_key(namespace))
  end

  def enqueue_job_at(redis, _namespace, job_serialized, jid, time, scheduled_queue) do
    score = Time.time_to_score(time)

    try do
      case Connection.zadd(redis, scheduled_queue, score, job_serialized,
             retry_on_connection_error: 3
           ) do
        {:ok, _} -> {:ok, jid}
        other -> other
      end
    catch
      :exit, e ->
        Logger.info("Error enqueueing -  #{Kernel.inspect(e)}")
        {:error, :timeout}
    end
  end

  @doc """
  Dequeue jobs for available queues
  """
  def dequeue(redis, namespace, node_id, queues) when is_list(queues) do
    dequeue_multiple(redis, namespace, node_id, queues)
  end

  defp dequeue_multiple(_redis, _namespace, _node_id, []) do
    {:ok, {:none, nil}}
  end

  defp dequeue_multiple(redis, namespace, node_id, queues) do
    deq_commands =
      Enum.map(queues, fn queue ->
        ["RPOPLPUSH", queue_key(namespace, queue), backup_queue_key(namespace, node_id, queue)]
      end)

    resp = Connection.qp(redis, deq_commands)

    case resp do
      {:error, reason} ->
        [{:error, reason}]

      {:ok, success} ->
        success
        |> Enum.zip(queues)
        |> Enum.map(fn {resp, queue} ->
          case resp do
            :undefined -> {:ok, {:none, queue}}
            nil -> {:ok, {:none, queue}}
            %Redix.Error{} = error -> {:error, {error, queue}}
            value -> {:ok, {value, queue}}
          end
        end)
    end
  end

  def re_enqueue_backup(redis, namespace, node_id, queue) do
    resp =
      Script.eval!(
        redis,
        :mlpop_rpush,
        [backup_queue_key(namespace, node_id, queue), queue_key(namespace, queue)],
        [10]
      )

    case resp do
      {:ok, [remaining, moved]} ->
        if moved > 0 do
          Logger.info(
            "Re-enqueued #{moved} job(s) from backup for node_id [#{node_id}] and queue [#{queue}]"
          )
        end

        if remaining > 0 do
          re_enqueue_backup(redis, namespace, node_id, queue)
        end

      _ ->
        nil
    end
  end

  def remove_job_from_backup(redis, namespace, node_id, queue, job_serialized) do
    Connection.lrem!(redis, backup_queue_key(namespace, node_id, queue), job_serialized, 1,
      retry_on_connection_error: 3
    )
  end

  def scheduler_dequeue(redis, namespace) do
    scheduler_dequeue(redis, namespace, Time.time_to_score())
  end

  def scheduler_dequeue(redis, namespace, max_score) do
    schedule_queues(namespace)
    |> Enum.map(
      &do_scheduler_dequeue(redis, namespace, &1, max_score, Config.get(:scheduler_page_size), 0)
    )
    |> Enum.sum()
  end

  defp do_scheduler_dequeue(redis, namespace, queue, max_score, limit, acc) do
    case Script.eval!(redis, :scheduler_dequeue, [queue], [
           limit,
           max_score,
           full_key(namespace, "")
         ]) do
      {:ok, count} ->
        if count == limit do
          do_scheduler_dequeue(redis, namespace, queue, max_score, limit, count + acc)
        else
          count + acc
        end

      {:error, reason} ->
        Logger.warn(
          "Error dequeueing jobs from scheduler queue #{queue} - #{Kernel.inspect(reason)}"
        )

        0
    end
  end

  def full_key("", key), do: key
  def full_key(nil, key), do: key

  def full_key(namespace, key) do
    "#{namespace}:#{key}"
  end

  def queue_key(namespace, queue) do
    full_key(namespace, "queue:#{queue}")
  end

  def backup_queue_key(namespace, node_id, queue) do
    full_key(namespace, "queue:backup::#{node_id}::#{queue}")
  end

  def schedule_queues(namespace) do
    [scheduled_queue_key(namespace), retry_queue_key(namespace)]
  end

  def scheduled_queue_key(namespace) do
    full_key(namespace, "schedule")
  end

  def retry_queue_key(namespace) do
    full_key(namespace, "retry")
  end

  def failed_queue_key(namespace) do
    full_key(namespace, "dead")
  end

  def retry_or_fail_job(redis, namespace, %{retry: retry} = job, error)
      when is_integer(retry) and retry > 0 do
    retry_or_fail_job(redis, namespace, job, error, retry)
  end

  def retry_or_fail_job(redis, namespace, %{retry: true} = job, error) do
    retry_or_fail_job(redis, namespace, job, error, get_max_retries())
  end

  def retry_or_fail_job(redis, namespace, job, error) do
    fail_job(redis, namespace, job, error)
  end

  defp retry_or_fail_job(redis, namespace, job, error, max_retries) do
    retry_count = (job.retry_count || 0) + 1

    if retry_count <= max_retries do
      retry_job(redis, namespace, job, retry_count, error)
    else
      Logger.info("Max retries on job #{job.jid} exceeded")
      fail_job(redis, namespace, job, error)
    end
  end

  def retry_job(redis, namespace, job, retry_count, error) do
    job =
      %{job | retry_count: retry_count, error_message: error}
      |> add_failure_timestamp()

    offset = Config.backoff().offset(job)
    time = Time.offset_from_now(offset)
    Logger.info("Queueing job #{job.jid} to retry in #{offset} seconds")

    {:ok, _jid} =
      enqueue_job_at(redis, namespace, Job.encode(job), job.jid, time, retry_queue_key(namespace))
  end

  def retry_job(redis, namespace, job) do
    remove_retry(redis, namespace, job.jid)
    {:ok, _jid} = enqueue(redis, namespace, Job.encode(job))
  end

  def fail_job(redis, namespace, job, error) do
    job =
      %{
        job
        | retry_count: job.retry_count || 0,
          error_class: "ExqGenericError",
          error_message: error
      }
      |> add_failure_timestamp()

    job_serialized = Job.encode(job)
    key = failed_queue_key(namespace)

    now = Time.unix_seconds()

    commands = [
      ["ZADD", key, Time.time_to_score(), job_serialized],
      ["ZREMRANGEBYSCORE", key, "-inf", now - Config.get(:dead_timeout_in_seconds)],
      ["ZREMRANGEBYRANK", key, 0, -Config.get(:dead_max_jobs) - 1]
    ]

    Connection.qp!(redis, commands, retry_on_connection_error: 3)
  end

  def queue_size(redis, namespace) do
    queues = list_queues(redis, namespace)
    for q <- queues, do: {q, queue_size(redis, namespace, q)}
  end

  def queue_size(redis, namespace, :scheduled) do
    Connection.zcard!(redis, scheduled_queue_key(namespace))
  end

  def queue_size(redis, namespace, :retry) do
    Connection.zcard!(redis, retry_queue_key(namespace))
  end

  def queue_size(redis, namespace, queue) do
    Connection.llen!(redis, queue_key(namespace, queue))
  end

  def delete_queue(redis, namespace, queue) do
    Connection.del!(redis, full_key(namespace, queue))
  end

  def jobs(redis, namespace) do
    queues = list_queues(redis, namespace)
    for q <- queues, do: {q, jobs(redis, namespace, q)}
  end

  def jobs(redis, namespace, queue, options \\ []) do
    range_start = Keyword.get(options, :offset, 0)
    range_end = range_start + Keyword.get(options, :size, @default_size) - 1

    Connection.lrange!(redis, queue_key(namespace, queue), range_start, range_end)
    |> maybe_decode(options)
  end

  def scheduled_jobs(redis, namespace, queue, options \\ []) do
    if Keyword.get(options, :score, false) do
      scheduled_jobs_with_scores(redis, namespace, queue, options)
    else
      Connection.zrangebyscorewithlimit!(
        redis,
        full_key(namespace, queue),
        Keyword.get(options, :offset, 0),
        Keyword.get(options, :size, @default_size)
      )
      |> maybe_decode(options)
    end
  end

  def scheduled_jobs_with_scores(redis, namespace, queue, options \\ []) do
    Connection.zrangebyscorewithscoreandlimit!(
      redis,
      full_key(namespace, queue),
      Keyword.get(options, :offset, 0),
      Keyword.get(options, :size, @default_size)
    )
    |> decode_zset_withscores(options)
  end

  def failed(redis, namespace, options \\ []) do
    if Keyword.get(options, :score, false) do
      Connection.zrevrangebyscorewithscoreandlimit!(
        redis,
        failed_queue_key(namespace),
        Keyword.get(options, :offset, 0),
        Keyword.get(options, :size, @default_size)
      )
      |> decode_zset_withscores(options)
    else
      Connection.zrevrangebyscorewithlimit!(
        redis,
        failed_queue_key(namespace),
        Keyword.get(options, :offset, 0),
        Keyword.get(options, :size, @default_size)
      )
      |> maybe_decode(options)
    end
  end

  def retry_size(redis, namespace) do
    Connection.zcard!(redis, retry_queue_key(namespace))
  end

  def scheduled_size(redis, namespace) do
    Connection.zcard!(redis, scheduled_queue_key(namespace))
  end

  def failed_size(redis, namespace) do
    Connection.zcard!(redis, failed_queue_key(namespace))
  end

  def remove_enqueued_jobs(redis, namespace, queue, raw_jobs) do
    Connection.lrem!(redis, queue_key(namespace, queue), raw_jobs)
  end

  def remove_job(redis, namespace, queue, jid) do
    {:ok, job} = find_job(redis, namespace, jid, queue, false)
    Connection.lrem!(redis, queue_key(namespace, queue), job)
  end

  def remove_retry(redis, namespace, jid) do
    {:ok, job} = find_job(redis, namespace, jid, :retry, false)
    Connection.zrem!(redis, retry_queue_key(namespace), job)
  end

  def remove_retry_jobs(redis, namespace, raw_jobs) do
    Connection.zrem!(redis, retry_queue_key(namespace), raw_jobs)
  end

  def dequeue_retry_jobs(redis, namespace, raw_jobs) do
    dequeue_scheduled_jobs(redis, namespace, retry_queue_key(namespace), raw_jobs)
  end

  def remove_scheduled(redis, namespace, jid) do
    {:ok, job} = find_job(redis, namespace, jid, :scheduled, false)
    Connection.zrem!(redis, scheduled_queue_key(namespace), job)
  end

  def remove_scheduled_jobs(redis, namespace, raw_jobs) do
    Connection.zrem!(redis, scheduled_queue_key(namespace), raw_jobs)
  end

  def dequeue_scheduled_jobs(redis, namespace, raw_jobs) do
    dequeue_scheduled_jobs(redis, namespace, scheduled_queue_key(namespace), raw_jobs)
  end

  def remove_failed_jobs(redis, namespace, raw_jobs) do
    Connection.zrem!(redis, failed_queue_key(namespace), raw_jobs)
  end

  def dequeue_failed_jobs(redis, namespace, raw_jobs) do
    dequeue_scheduled_jobs(redis, namespace, failed_queue_key(namespace), raw_jobs)
  end

  def list_queues(redis, namespace) do
    Connection.smembers!(redis, full_key(namespace, "queues"))
  end

  @doc """
  Find a current job by job id (but do not pop it)
  """
  def find_job(redis, namespace, jid, queue) do
    find_job(redis, namespace, jid, queue, true)
  end

  def find_job(redis, namespace, jid, :scheduled, convert) do
    redis
    |> Connection.zrangebyscore!(scheduled_queue_key(namespace))
    |> search_jobs(jid, convert)
  end

  def find_job(redis, namespace, jid, :retry, convert) do
    redis
    |> Connection.zrangebyscore!(retry_queue_key(namespace))
    |> search_jobs(jid, convert)
  end

  def find_job(redis, namespace, jid, queue, convert) do
    redis
    |> Connection.lrange!(queue_key(namespace, queue))
    |> search_jobs(jid, convert)
  end

  def search_jobs(jobs_serialized, jid) do
    search_jobs(jobs_serialized, jid, true)
  end

  def search_jobs(jobs_serialized, jid, true) do
    found_job =
      jobs_serialized
      |> Enum.map(&Job.decode/1)
      |> Enum.find(fn job -> job.jid == jid end)

    {:ok, found_job}
  end

  def search_jobs(jobs_serialized, jid, false) do
    found_job =
      jobs_serialized
      |> Enum.find(fn job_serialized ->
        job = Job.decode(job_serialized)
        job.jid == jid
      end)

    {:ok, found_job}
  end

  def to_job_serialized(queue, worker, args, options) do
    to_job_serialized(queue, worker, args, options, Time.unix_seconds())
  end

  def to_job_serialized(queue, worker, args, options, enqueued_at) when is_atom(worker) do
    to_job_serialized(queue, to_string(worker), args, options, enqueued_at)
  end

  def to_job_serialized(queue, "Elixir." <> worker, args, options, enqueued_at) do
    to_job_serialized(queue, worker, args, options, enqueued_at)
  end

  def to_job_serialized(queue, worker, args, options, enqueued_at) do
    jid = Keyword.get_lazy(options, :jid, fn -> UUID.uuid4() end)
    retry = Keyword.get_lazy(options, :max_retries, fn -> get_max_retries() end)

    job = %{
      queue: queue,
      retry: retry,
      class: worker,
      args: args,
      jid: jid,
      enqueued_at: enqueued_at
    }

    {jid, Config.serializer().encode!(job)}
  end

  defp dequeue_scheduled_jobs(redis, namespace, queue_key, raw_jobs) do
    Script.eval!(redis, :scheduler_dequeue_jobs, [queue_key, full_key(namespace, "")], raw_jobs)
  end

  defp get_max_retries do
    :max_retries
    |> Config.get()
    |> Exq.Support.Coercion.to_integer()
  end

  defp add_failure_timestamp(job) do
    timestamp = Time.unix_seconds()

    job =
      if !job.failed_at do
        %{job | failed_at: timestamp}
      else
        job
      end

    %{job | retried_at: timestamp}
  end

  defp decode_zset_withscores(list, options) do
    raw? = Keyword.get(options, :raw, false)

    Enum.chunk_every(list, 2)
    |> Enum.map(fn [job, score] ->
      if raw? do
        {job, score}
      else
        {Job.decode(job), score}
      end
    end)
  end

  defp maybe_decode(list, options) do
    if Keyword.get(options, :raw, false) do
      list
    else
      Enum.map(list, &Job.decode/1)
    end
  end
end
