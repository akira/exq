defmodule Exq.RedisQueue do
  use Timex

  @default_queue "default"

  def find_job(redis, namespace, jid, queue) do
    jobs = Exq.Redis.lrange!(redis, queue_key(namespace, queue))

    finder = fn({j, idx}) ->
      job = Exq.Job.from_json(j)
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
  def enqueue(redis, namespace, queue, job_json) do
    [{:ok, _}, {:ok, _}] = :eredis.qp(redis, [
      ["SADD", full_key(namespace, "queues"), queue],
      ["RPUSH", queue_key(namespace, queue), job_json]])
  end

  def enqueue_at(redis, namespace, queue, time, worker, args) do
    {jid, job_json} = to_job_json(queue, worker, args)
    score = round(time)
    Exq.Redis.zadd!(redis, scheduled_queue_key(namespace, queue), score, job_json)
    jid
  end

  def enqueue_in(redis, namespace, queue, offset, worker, args) do
    {jid, job_json} = to_job_json(queue, worker, args)
    score = round(Time.now(:secs) + offset)
    Exq.Redis.zadd!(redis, scheduled_queue_key(namespace, queue), score, job_json)
    jid
  end

  def dequeue(redis, namespace, queues) when is_list(queues) do
    dequeue_random(redis, namespace, queues)
  end
  def dequeue(redis, namespace, queue) do
    {Exq.Redis.lpop!(redis, queue_key(namespace, queue)), queue}
  end

  def scheduler_dequeue(redis, namespace, queues) do
    max_score = round(Time.now(:secs))
    Exq.Shuffle.shuffle(queues)
      |> Enum.each(fn(queue) ->
        Exq.Redis.zrangebyscore!(redis, scheduled_queue_key(namespace, queue), 0, max_score)
          |> scheduler_dequeue_requeue(redis, namespace, queue, 0)
      end)
  end

  def scheduler_dequeue_requeue([], _redis, _namespace, _queue, count), do: count
  def scheduler_dequeue_requeue([h|t], redis, namespace, queue, count) do
    if Exq.Redis.zrem!(redis, scheduled_queue_key(namespace, queue), h) == "1" do
      enqueue(redis, namespace, queue, h)
      count = count + 1
    end
    scheduler_dequeue_requeue(t, redis, namespace, queue, count)
  end


  def full_key("", key), do: key
  def full_key(nil, key), do: key
  def full_key(namespace, key) do
    "#{namespace}:#{key}"
  end

  def queue_key(namespace, queue) do
    full_key(namespace, "queue:#{queue}")
  end

  def scheduled_queue_key(namespace, queue) do
    full_key(namespace, "scheduled:#{queue}")
  end

  defp dequeue_random(_redis, _namespace, []) do
    {nil, nil}
  end
  defp dequeue_random(redis, namespace, queues) do
    [h | rq]  = Exq.Shuffle.shuffle(queues)
    case dequeue(redis, namespace, h) do
      {nil, _} -> dequeue_random(redis, namespace, rq)
      {job, q} -> {job, q}
    end
  end

  defp to_job_json(queue, worker, args) do
    jid = UUID.uuid4
    job = Enum.into([{:queue, queue}, {:class, worker}, {:args, args}, {:jid, jid}, {:enqueued_at, DateFormat.format!(Date.local, "{ISO}")}], HashDict.new)
    {jid, Exq.Json.encode!(job)}
  end
end
