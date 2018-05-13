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
  alias Exq.Support.Job
  alias Exq.Support.Config
  alias Exq.Support.Time

  def enqueue(redis, namespace, queue, worker, args, options) do
    {jid, job_serialized} = to_job_serialized(queue, worker, args, options)
    case enqueue(redis, namespace, queue, job_serialized) do
      :ok    -> {:ok, jid}
      other  -> other
    end
  end
  def enqueue(redis, namespace, job_serialized) do
    job = Config.serializer.decode_job(job_serialized)
    case enqueue(redis, namespace, job.queue, job_serialized) do
      :ok   -> {:ok, job.jid}
      error -> error
    end

  end
  def enqueue(redis, namespace, queue, job_serialized) do
    try do
      response = Connection.qp(redis, [
        ["SADD", full_key(namespace, "queues"), queue],
        ["LPUSH", queue_key(namespace, queue), job_serialized]])

      case response do
        {:ok, [%Redix.Error{}, %Redix.Error{}]} = error -> error
        {:ok, [%Redix.Error{}, _]} = error -> error
        {:ok, [_, %Redix.Error{}]} = error -> error
        {:ok, [_, _]} -> :ok
        other    -> other
      end
    catch
      :exit, e ->
        Logger.info("Error enqueueing -  #{Kernel.inspect e}")
        {:error, :timeout}
    end
  end

  def enqueue_in(redis, namespace, queue, offset, worker, args, options) when is_integer(offset) do
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
      case Connection.zadd(redis, scheduled_queue, score, job_serialized) do
        {:ok, _} -> {:ok, jid}
        other    -> other
      end
    catch
      :exit, e ->
        Logger.info("Error enqueueing -  #{Kernel.inspect e}")
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
    deq_commands = Enum.map(queues, fn(queue) ->
      ["RPOPLPUSH", queue_key(namespace, queue), backup_queue_key(namespace, node_id, queue)]
    end)
    resp = Connection.qp(redis, deq_commands)

    case resp do
      {:error, reason} -> [{:error, reason}]
      {:ok, success} ->
        success |> Enum.zip(queues) |> Enum.map(fn({resp, queue}) ->
          case resp do
            :undefined -> {:ok, {:none, queue}}
            nil        -> {:ok, {:none, queue}}
            %Redix.Error{} = error  -> {:error, {error, queue}}
            value      -> {:ok, {value, queue}}
          end
        end)
    end
  end

  def re_enqueue_backup(redis, namespace, node_id, queue) do
    resp = redis |> Connection.rpoplpush(
      backup_queue_key(namespace, node_id, queue),
      queue_key(namespace, queue))
    case resp do
      {:ok, job} ->
        if String.valid?(job) do
          Logger.info("Re-enqueueing job from backup for node_id [#{node_id}] and queue [#{queue}]")
          re_enqueue_backup(redis, namespace, node_id, queue)
        end
      _ -> nil
    end
  end

  def remove_job_from_backup(redis, namespace, node_id, queue, job_serialized) do
    Connection.lrem!(redis, backup_queue_key(namespace, node_id, queue), job_serialized)
  end

  def scheduler_dequeue(redis, namespace) do
    scheduler_dequeue(redis, namespace, Time.time_to_score, Config.get(:scheduler_page_size))
  end
  def scheduler_dequeue(redis, namespace, max_score, page_size) do
    queues = schedule_queues(namespace)
    commands = Enum.map(queues, &(["ZRANGEBYSCORE", &1, 0, max_score, "LIMIT", 0, page_size]))
    resp = Connection.qp(redis, commands)
    case resp do
      {:error, reason} -> [{:error, reason}]
      {:ok, responses} ->
        queues
        |> Enum.zip(responses)
        |> Enum.reduce(0, fn({queue, response}, acc) ->
          case response do
            jobs when is_list(jobs) ->
              deq_count = scheduler_dequeue_requeue(jobs, redis, namespace, queue, 0)
              deq_count + acc
            %Redix.Error{} = reason ->
             Logger.error("Redis error scheduler dequeue #{Kernel.inspect(reason)}}.")
             acc
          end
        end)
    end
  end

  def scheduler_dequeue_requeue([], _redis, _namespace, _schedule_queue, count), do: count
  def scheduler_dequeue_requeue([job_serialized|t], redis, namespace, schedule_queue, count) do
    resp = Connection.zrem(redis, schedule_queue, job_serialized)
    count = case resp do
      {:ok, 1} ->
        enqueue(redis, namespace, job_serialized)
        count + 1
      {:ok, _} -> count
      {:error, reason} ->
        Logger.error("Redis error scheduler dequeue #{Kernel.inspect(reason)}}.")
        count
    end
    scheduler_dequeue_requeue(t, redis, namespace, schedule_queue, count)
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
    [ scheduled_queue_key(namespace), retry_queue_key(namespace) ]
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

  def retry_or_fail_job(redis, namespace, %{retry: retry} = job, error) when is_integer(retry) and retry > 0 do
    retry_or_fail_job(redis, namespace, job, error, retry)
  end
  def retry_or_fail_job(redis, namespace, %{retry: true} = job, error) do
    retry_or_fail_job(redis, namespace, job, error, Config.get(:max_retries))
  end
  def retry_or_fail_job(redis, namespace, job, error) do
    fail_job(redis, namespace, job, error)
  end

  defp retry_or_fail_job(redis, namespace, job, error, max_retries) do
    retry_count = (job.retry_count || 0) + 1
    if (retry_count <= max_retries) do
      retry_job(redis, namespace, job, retry_count, error)
    else
      Logger.info("Max retries on job #{job.jid} exceeded")
      fail_job(redis, namespace, job, error)
    end
  end

  def retry_job(redis, namespace, job, retry_count, error) do
      job = %{job |
        failed_at: Time.unix_seconds,
        retry_count: retry_count,
        error_message: error
      }

      offset = Config.backoff.offset(job)
      time = Time.offset_from_now(offset)
      Logger.info("Queueing job #{job.jid} to retry in #{offset} seconds")
      enqueue_job_at(redis, namespace, Job.encode(job), job.jid, time, retry_queue_key(namespace))
  end
  def retry_job(redis, namespace, job) do
    remove_retry(redis, namespace, job.jid)
    enqueue(redis, namespace, Job.encode(job))
  end

  def fail_job(redis, namespace, job, error) do
    job = %{job | failed_at: Time.unix_seconds, retry_count: job.retry_count || 0,
      error_class: "ExqGenericError", error_message: error}
    job_serialized = Job.encode(job)
    key = failed_queue_key(namespace)

    now = Time.unix_seconds()
    commands = [
      ["ZADD", key, Time.time_to_score(), job_serialized],
      ["ZREMRANGEBYSCORE", key, "-inf", now - Config.get(:dead_timeout_in_seconds)],
      ["ZREMRANGEBYRANK", key, 0, -Config.get(:dead_max_jobs) - 1]
    ]

    Connection.qp!(redis, commands)
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

  def jobs(redis, namespace, queue) do
    Connection.lrange!(redis, queue_key(namespace, queue))
    |> Enum.map(&Job.decode/1)
  end

  def scheduled_jobs(redis, namespace, queue) do
    Connection.zrangebyscore!(redis, full_key(namespace, queue))
    |> Enum.map(&Job.decode/1)
  end

  def scheduled_jobs_with_scores(redis, namespace, queue) do
    Connection.zrangebyscorewithscore!(redis, full_key(namespace, queue))
    |> Enum.chunk(2)
    |> Enum.map( fn([job, score]) -> {Job.decode(job), score} end)
  end

  def failed(redis, namespace) do
    Connection.zrange!(redis, failed_queue_key(namespace))
    |> Enum.map(&Job.decode/1)
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

  def remove_job(redis, namespace, queue, jid) do
    {:ok, job} = find_job(redis, namespace, jid, queue, false)
    Connection.lrem!(redis, queue_key(namespace, queue), job)
  end

  def remove_retry(redis, namespace, jid) do
    {:ok, job} = find_job(redis, namespace, jid, :retry, false)
    Connection.zrem!(redis, retry_queue_key(namespace), job)
  end

  def remove_scheduled(redis, namespace, jid) do
    {:ok, job} = find_job(redis, namespace, jid, :scheduled, false)
    Connection.zrem!(redis, scheduled_queue_key(namespace), job)
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
    found_job = jobs_serialized
    |> Enum.map(&Job.decode/1)
    |> Enum.find(fn job -> job.jid == jid end)
    {:ok, found_job}
  end
  def search_jobs(jobs_serialized, jid, false) do
    found_job = jobs_serialized
    |> Enum.find(fn job_serialized ->
      job = Job.decode(job_serialized)
      job.jid == jid
    end)
    {:ok, found_job}
  end

  def to_job_serialized(queue, worker, args, options) do
    to_job_serialized(queue, worker, args, options, Time.unix_seconds)
  end
  def to_job_serialized(queue, worker, args, options, enqueued_at) when is_atom(worker) do
    to_job_serialized(queue, to_string(worker), args, options, enqueued_at)
  end
  def to_job_serialized(queue, "Elixir." <> worker, args, options, enqueued_at) do
    to_job_serialized(queue, worker, args, options, enqueued_at)
  end
  def to_job_serialized(queue, worker, args, options, enqueued_at) do
    jid = UUID.uuid4
    retry = Keyword.get_lazy(options, :max_retries, fn() -> Config.get(:max_retries) end)
    job = %{queue: queue, retry: retry, class: worker, args: args, jid: jid, enqueued_at: enqueued_at}
    {jid, Config.serializer.encode!(job)}
  end
end
