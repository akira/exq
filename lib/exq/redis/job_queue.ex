defmodule Exq.Redis.JobQueue do
  use Timex
  require Logger

  alias Exq.Redis.Connection
  alias Exq.Support.Json
  alias Exq.Support.Job
  alias Exq.Support.Config
  alias Exq.Support.Randomize

  #TODO: set to 25
  @default_max_retries 5
  @default_queue "default"

  def find_job(redis, namespace, jid, :scheduled) do
    Connection.zrangebyscore!(redis, scheduled_queue_key(namespace))
      |> find_job(jid)
  end
  def find_job(redis, namespace, jid, queue) do
    Connection.lrange!(redis, queue_key(namespace, queue))
      |> find_job(jid)
  end

  def find_job(jobs, jid) do

    finder = fn({j, _idx}) ->
      job = Exq.Support.Job.from_json(j)
      job.jid == jid
    end

    error = Enum.find(Enum.with_index(jobs), finder)

    case error do
      nil ->
        {:not_found, nil}
      _ ->
        {job, idx} = error
        {:ok, job, idx}
    end
  end

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
      response = Redix.pipeline(redis, [
        ["SADD", full_key(namespace, "queues"), queue],
        ["LPUSH", queue_key(namespace, queue), job_json]], [timeout: Config.get(:redis_timeout, 5000)])

      case response do
        {:ok, [%Redix.Error{}, %Redix.Error{}]} = error -> error
        {:ok, [%Redix.Error{}, _]} = error -> error
        {:ok, [_, %Redix.Error{}]} = error -> error
        {:ok, [_, _]} = error -> :ok
        other    -> other
      end
    catch
      :exit, e ->
        Logger.info("Error enqueueing -  #{Kernel.inspect e}")
        {:error, :timeout}
    end
  end

  def enqueue_in(redis, namespace, queue, offset, worker, args) when is_integer(offset) do
    time = Time.add(Time.now, Time.from(offset * 1_000_000, :usecs))
    enqueue_at(redis, namespace, queue, time, worker, args)
  end
  def enqueue_at(redis, namespace, queue, time, worker, args) do
    enqueued_at = DateFormat.format!(Date.from(time, :timestamp) |> Date.universal, "{ISO}")
    {jid, job_json} = to_job_json(queue, worker, args, enqueued_at)
    enqueue_job_at(redis, namespace, job_json, jid, time, scheduled_queue_key(namespace))
  end

  def enqueue_job_at(redis, namespace, job_json, jid, time, scheduled_queue) do
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

  def dequeue(redis, namespace, queues) when is_list(queues) do
    dequeue_random(redis, namespace, queues)
  end
  def dequeue(redis, namespace, queue) do
    # normalize empty return values
    case Connection.rpoplpush(redis, queue_key(namespace, queue), backup_queue_key(namespace, queue)) do
      {status, :undefined} -> {status, {:none, queue}}
      {status, nil}        -> {status, {:none, queue}}
      {status, value}      -> {status, {value, queue}}
    end
  end

  def scheduler_dequeue(redis, namespace, queues) when is_list(queues) do
    scheduler_dequeue(redis, namespace, queues, time_to_score(Time.now))
  end
  def scheduler_dequeue(redis, namespace, queues, max_score) when is_list(queues) do
    Enum.reduce(schedule_queues(namespace), 0, fn(schedule_queue, acc) ->
      deq_count = Connection.zrangebyscore!(redis, schedule_queue, 0, max_score)
        |> scheduler_dequeue_requeue(redis, namespace, queues, schedule_queue, 0)
      deq_count + acc
    end)
  end

  def scheduler_dequeue_requeue([], _redis, _namespace, _queues, schedule_queue, count), do: count
  def scheduler_dequeue_requeue([job_json|t], redis, namespace, queues, schedule_queue, count) do
    if Connection.zrem!(redis, schedule_queue, job_json) == 1 do
      if Enum.count(queues) == 1 do
        enqueue(redis, namespace, hd(queues), job_json)
      else
        enqueue(redis, namespace, job_json)
      end
      count = count + 1
    end
    scheduler_dequeue_requeue(t, redis, namespace, queues, schedule_queue, count)
  end


  def full_key("", key), do: key
  def full_key(nil, key), do: key
  def full_key(namespace, key) do
    "#{namespace}:#{key}"
  end

  def queue_key(namespace, queue) do
    full_key(namespace, "queue:#{queue}")
  end

  def backup_queue_key(namespace, queue) do
    full_key(namespace, "queue:backup::#{queue}")
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

  def time_to_score(time) do
    Float.to_string(time |> Time.to_secs, [decimals: 6])
  end

  def retry_or_fail_job(redis, namespace, %{retry: true} = job, error) do
    retry_count = (job.retry_count || 0) + 1
    max_retries = Config.get(:max_retries, @default_max_retries)

    if (retry_count <= max_retries) do
      job = %{job |
        retry_count: retry_count,
        error_message: error
      }

      # Similar to Sidekiq strategy
      offset = :math.pow(job.retry_count, 4) + 15 + (Randomize.random(30) * (job.retry_count + 1))
      time = Time.add(Time.now, Time.from(offset * 1_000_000, :usecs))
      Logger.info("Queueing job #{job.jid} to retry in #{offset} seconds")
      enqueue_job_at(redis, namespace, Job.to_json(job), job.jid, time, retry_queue_key(namespace))
    else
      Logger.info("Max retries on job #{job.jid} exceeded")
      fail_job(redis, namespace, job, error)
    end
  end
  def retry_or_fail_job(redis, namespace, job, error) do
    fail_job(redis, namespace, job, error)
  end

  def fail_job(redis, namespace, job, error) do
    failed_at = DateFormat.format!(Date.universal, "{ISO}")
    job = %{job | failed_at: failed_at, error_class: "ExqGenericError", error_message: error}
    job_json = Job.to_json(job)
    Connection.lpush!(redis, full_key(namespace, "failed"), job_json)
  end

  defp dequeue_random(_redis, _namespace, []) do
    {:ok, {:none, nil}}
  end
  defp dequeue_random(redis, namespace, queues) do
    [h | rq]  = Exq.Support.Shuffle.shuffle(queues)
    case dequeue(redis, namespace, h) do
      {:ok, {:none, _}}      -> dequeue_random(redis, namespace, rq)
      {:ok, {job, q}}        -> {:ok, {job, q}}
      {:error, reason}       -> {:error, reason}
    end
  end

  def to_job_json(queue, worker, args) do
    to_job_json(queue, worker, args, DateFormat.format!(Date.universal, "{ISO}"))
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
