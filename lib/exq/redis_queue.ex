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
    {jid, job} = job_json(queue, worker, args)
    [{:ok, _}, {:ok, _}] = :eredis.qp(redis, [
      ["SADD", full_key(namespace, "queues"), queue],
      ["RPUSH", queue_key(namespace, queue), job]])
    jid
  end

  def dequeue(redis, namespace, queues) when is_list(queues) do
    dequeue_random(redis, namespace, queues)
  end
  def dequeue(redis, namespace, queue) do
    {Exq.Redis.lpop!(redis, queue_key(namespace, queue)), queue}
  end

  def full_key("", key), do: key
  def full_key(nil, key), do: key
  def full_key(namespace, key) do
    "#{namespace}:#{key}"
  end

  def queue_key(namespace, queue) do
    full_key(namespace, "queue:#{queue}")
  end

  defp dequeue_random(redis, namespace, []) do
    {nil, nil}
  end
  defp dequeue_random(redis, namespace, queues) do
    [h | rq]  = Exq.Shuffle.shuffle(queues)
    case dequeue(redis, namespace, h) do
      {nil, _} -> dequeue_random(redis, namespace, rq)
      {job, q} -> {job, q}
    end
  end

  defp job_json(queue, worker, args) do
    jid = UUID.uuid4
    job = Enum.into([{:queue, queue}, {:class, worker}, {:args, args}, {:jid, jid}, {:enqueued_at, DateFormat.format!(Date.local, "{ISO}")}], HashDict.new)
    {jid, Exq.Json.encode(job)}
  end
end
