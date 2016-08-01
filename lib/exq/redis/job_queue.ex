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

  use Timex
  require Logger

  alias Exq.Redis.Connection
  alias Exq.Support.Json
  alias Exq.Support.Job
  alias Exq.Support.Config
  alias Exq.Support.Randomize

  def enqueue(redis, namespace, queue, worker, args) do
    {jid, job_json} = to_job_json(queue, worker, args)
    case enqueue(redis, namespace, queue, job_json) do
      :ok    -> {:ok, jid}
      other  -> other
    end
  end
  def enqueue(redis, namespace, job_json) do
    job = Json.decode!(job_json)
    case enqueue(redis, namespace, job["queue"], job_json) do
      :ok   -> {:ok, job["jid"]}
      error -> error
    end

  end
  def enqueue(redis, namespace, queue, job_json) do
    try do
      response = Connection.qp(redis, [
        ["SADD", full_key(namespace, "queues"), queue],
        ["LPUSH", queue_key(namespace, queue), job_json]])

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

  def enqueue_in(redis, namespace, queue, offset, worker, args) when is_integer(offset) do
    time = Timex.add(Timex.now, Timex.Duration.from_microseconds(offset * 1_000_000))
    enqueue_at(redis, namespace, queue, time, worker, args)
  end
  def enqueue_at(redis, namespace, queue, time, worker, args) do
    {jid, job_json} = to_job_json(queue, worker, args)
    enqueue_job_at(redis, namespace, job_json, jid, time, scheduled_queue_key(namespace))
  end

  def enqueue_job_at(redis, _namespace, job_json, jid, time, scheduled_queue) do
    score = time_to_score(time)
    try do
      case Connection.zadd(redis, scheduled_queue, score, job_json) do
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
  def dequeue(redis, namespace, host, queues) when is_list(queues) do
    dequeue_multiple(redis, namespace, host, queues)
  end

  defp dequeue_multiple(_redis, _namespace, _host, []) do
    {:ok, {:none, nil}}
  end
  defp dequeue_multiple(redis, namespace, host, queues) do
    deq_commands = Enum.map(queues, fn(queue) ->
      ["RPOPLPUSH", queue_key(namespace, queue), backup_queue_key(namespace, host, queue)]
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

  def re_enqueue_backup(redis, namespace, host, queue) do
    resp = redis |> Connection.rpoplpush(
      backup_queue_key(namespace, host, queue),
      queue_key(namespace, queue))
    case resp do
      {:ok, job} ->
        if String.valid?(job) do
          Logger.info("Re-enqueueing job from backup for host [#{host}] and queue [#{queue}]")
          re_enqueue_backup(redis, namespace, host, queue)
        end
      _ -> nil
    end
  end

  def remove_job_from_backup(redis, namespace, host, queue, job_json) do
    Connection.lrem!(redis, backup_queue_key(namespace, host, queue), job_json)
  end

  def scheduler_dequeue(redis, namespace) do
    scheduler_dequeue(redis, namespace, time_to_score(Timex.now))
  end
  def scheduler_dequeue(redis, namespace, max_score) do
    queues = schedule_queues(namespace)
    commands = Enum.map(queues, &(["ZRANGEBYSCORE", &1, 0, max_score]))
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
  def scheduler_dequeue_requeue([job_json|t], redis, namespace, schedule_queue, count) do
    resp = Connection.zrem(redis, schedule_queue, job_json)
    count = case resp do
      {:ok, 1} ->
        enqueue(redis, namespace, job_json)
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

  def backup_queue_key(namespace, host, queue) do
    full_key(namespace, "queue:backup::#{host}::#{queue}")
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

  def time_to_score(time) do
	DateTime.to_unix(time, :microseconds)/1_000_000
	|> Float.to_string([decimals: 6])
  end

  def retry_or_fail_job(redis, namespace, %{retry: true} = job, error) do
    retry_or_fail_job(redis, namespace, job, error, Config.get(:max_retries))
  end
  def retry_or_fail_job(redis, namespace, %{retry: retry} = job, error) when is_integer(retry) do
    retry_or_fail_job(redis, namespace, job, error, retry)
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
        failed_at: Timex.format!(DateTime.utc_now, "{ISO:Extended}"),
        retry_count: retry_count,
        error_message: error
      }

      # Similar to Sidekiq strategy
      offset = :math.pow(job.retry_count, 4) + 15 + (Randomize.random(30) * (job.retry_count + 1))
      time = Timex.add(Timex.now, Timex.Duration.from_microseconds(offset * 1_000_000))
      Logger.info("Queueing job #{job.jid} to retry in #{offset} seconds")
      enqueue_job_at(redis, namespace, Job.to_json(job), job.jid, time, retry_queue_key(namespace))
  end

  def fail_job(redis, namespace, job, error) do
    failed_at = Timex.format!(DateTime.utc_now, "{ISO:Extended}")
    job = %{job | failed_at: failed_at, retry_count: job.retry_count || 0,
      error_class: "ExqGenericError", error_message: error}
    job_json = Job.to_json(job)
    Connection.zadd!(redis, full_key(namespace, "dead"), time_to_score(Timex.now), job_json)
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
    |> Enum.map(&Job.from_json/1)
  end

  def scheduled_jobs(redis, namespace, queue) do
    Connection.zrangebyscore!(redis, full_key(namespace, queue))
    |> Enum.map(&Job.from_json/1)
  end

  def scheduled_jobs_with_scores(redis, namespace, queue) do
    Connection.zrangebyscorewithscore!(redis, full_key(namespace, queue))
    |> Enum.chunk(2)
    |> Enum.map( fn([job, score]) -> {Job.from_json(job), score} end)
  end

  def failed(redis, namespace) do
    Connection.zrange!(redis, failed_queue_key(namespace))
    |> Enum.map(&Job.from_json/1)
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

  def search_jobs(jobs_json, jid) do
    search_jobs(jobs_json, jid, true)
  end
  def search_jobs(jobs_json, jid, true) do
    found_job = jobs_json
    |> Enum.map(&Job.from_json/1)
    |> Enum.find(fn job -> job.jid == jid end)
    {:ok, found_job}
  end
  def search_jobs(jobs_json, jid, false) do
    found_job = jobs_json
    |> Enum.find(fn job_json ->
      job = Job.from_json(job_json)
      job.jid == jid
    end)
    {:ok, found_job}
  end

  def to_job_json(queue, worker, args) do
    to_job_json(queue, worker, args, Timex.Duration.now(:microseconds) / 1_000_000.0)
  end
  def to_job_json(queue, worker, args, enqueued_at) when is_atom(worker) do
    to_job_json(queue, to_string(worker), args, enqueued_at)
  end
  def to_job_json(queue, "Elixir." <> worker, args, enqueued_at) do
    to_job_json(queue, worker, args, enqueued_at)
  end
  def to_job_json(queue, worker, args, enqueued_at) do
    jid = UUID.uuid4
    job = Enum.into([{:queue, queue}, {:retry, true}, {:class, worker}, {:args, args}, {:jid, jid}, {:enqueued_at, enqueued_at}], HashDict.new)
    {jid, Json.encode!(job)}
  end
end
