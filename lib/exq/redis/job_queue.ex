defmodule Exq.Redis.JobQueue do
  use Timex

  alias Exq.Redis.Connection
  alias Exq.Support.Json
  alias Exq.Support.Config

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
    enqueue(redis, namespace, queue, job_json)
    jid
  end
  def enqueue(redis, namespace, job_json) do
    job = Json.decode!(job_json)
    enqueue(redis, namespace, job["queue"], job_json)
    job["jid"]
  end
  def enqueue(redis, namespace, queue, job_json) do
    [{:ok, _}, {:ok, _}] = :eredis.qp(redis, [
      ["SADD", full_key(namespace, "queues"), queue],
      ["RPUSH", queue_key(namespace, queue), job_json]], Config.get(:redis_timeout, 5000))
  end

  def enqueue_in(redis, namespace, queue, offset, worker, args) do
    time = Time.add(Time.now, Time.from(offset * 1_000_000, :usecs))
    enqueue_at(redis, namespace, queue, time, worker, args)
  end

  def enqueue_at(redis, namespace, queue, time, worker, args) do
    enqueued_at = DateFormat.format!(Date.from(time, :timestamp) |> Date.local, "{ISO}")
    {jid, job_json} = to_job_json(queue, worker, args, enqueued_at)
    score = time_to_score(time)
    Connection.zadd!(redis, scheduled_queue_key(namespace), score, job_json)
    jid
  end

  def dequeue(redis, namespace, queues) when is_list(queues) do
    dequeue_random(redis, namespace, queues)
  end
  def dequeue(redis, namespace, queue) do
    {Connection.lpop!(redis, queue_key(namespace, queue)), queue}
  end

  def scheduler_dequeue(redis, namespace, queues) when is_list(queues) do
    scheduler_dequeue(redis, namespace, queues, time_to_score(Time.now))
  end
  def scheduler_dequeue(redis, namespace, queues, max_score) when is_list(queues) do
    Connection.zrangebyscore!(redis, scheduled_queue_key(namespace), 0, max_score)
      |> scheduler_dequeue_requeue(redis, namespace, queues, 0)
  end

  def scheduler_dequeue_requeue([], _redis, _namespace, _queues, count), do: count
  def scheduler_dequeue_requeue([job_json|t], redis, namespace, queues, count) do
    if Connection.zrem!(redis, scheduled_queue_key(namespace), job_json) == "1" do
      if Enum.count(queues) == 1 do
        enqueue(redis, namespace, hd(queues), job_json)
      else
        enqueue(redis, namespace, job_json)
      end
      count = count + 1
    end
    scheduler_dequeue_requeue(t, redis, namespace, queues, count)
  end


  def full_key("", key), do: key
  def full_key(nil, key), do: key
  def full_key(namespace, key) do
    "#{namespace}:#{key}"
  end

  def queue_key(namespace, queue) do
    full_key(namespace, "queue:#{queue}")
  end

  def scheduled_queue_key(namespace) do
    full_key(namespace, "schedule")
  end

  def time_to_score(time) do
    Float.to_string(time |> Time.to_secs, [decimals: 6])
  end

  defp dequeue_random(_redis, _namespace, []) do
    {:none, nil}
  end
  defp dequeue_random(redis, namespace, queues) do
    [h | rq]  = Exq.Support.Shuffle.shuffle(queues)
    case dequeue(redis, namespace, h) do
      {nil, _} -> dequeue_random(redis, namespace, rq)
      {:none, _} -> dequeue_random(redis, namespace, rq)
      {job, q} -> {job, q}
    end
  end

  def to_job_json(queue, worker, args) do
    to_job_json(queue, worker, args, DateFormat.format!(Date.local, "{ISO}"))
  end
  def to_job_json(queue, worker, args, enqueued_at) when is_atom(worker) do
    to_job_json(queue, to_string(worker), args, enqueued_at)
  end
  def to_job_json(queue, "Elixir." <> worker, args, enqueued_at) do
    to_job_json(queue, worker, args, enqueued_at)
  end
  def to_job_json(queue, worker, args, enqueued_at) do
    jid = UUID.uuid4
    job = Enum.into([{:queue, queue}, {:class, worker}, {:args, args}, {:jid, jid}, {:enqueued_at, enqueued_at}], HashDict.new)
    {jid, Json.encode!(job)}
  end
end
