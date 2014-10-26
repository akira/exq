defmodule Exq.RedisQueue do

  @default_queue "default"

  def enqueue(redis, namespace, queue, worker, args) do
    Exq.Redis.sadd!(redis, full_key(namespace, "queues"), queue)
    [jid, job] = job_json(queue, worker, args)
    Exq.Redis.rpush!(redis, queue_key(namespace, queue), job)
    jid
  end

  def dequeue(redis, namespace, queues) when is_list(queues) do
    dequeue_random(redis, namespace, queues)
  end
  def dequeue(redis, namespace, queue) do
    Exq.Redis.lpop!(redis, queue_key(namespace, queue))
  end

  defp full_key(namespace, key) do
    "#{namespace}:#{key}"
  end

  defp queue_key(namespace, queue) do
    full_key(namespace, "queue:#{queue}")
  end

  defp dequeue_random(redis, namespace, []) do
    nil
  end
  defp dequeue_random(redis, namespace, queues) do
    [h | rq]  = Exq.Shuffle.shuffle(queues)
    case dequeue(redis, namespace, h) do
      nil -> dequeue_random(redis, namespace, rq)
      job -> job
    end
  end

  defp job_json(queue, worker, args) do
    jid = UUID.uuid4
    job = Enum.into([{:queue, queue}, {:class, worker}, {:args, args}, {:jid, jid}], HashDict.new)
    [jid, JSEX.encode!(job)]
  end
end
