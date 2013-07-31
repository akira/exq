defmodule JobQueue do 

  @default_queue "default"

  def enqueue(redis, namespace, queue, worker, args) do
    Redis.sadd!(redis, full_key(namespace, "queues"), queue)
    Redis.rpush!(redis, queue_key(namespace, queue),
      job_json(queue, worker, args))
  end

  def dequeue(redis, namespace, queues) when is_list(queues) do 
    dequeue_random(redis, namespace, queues)
  end
  def dequeue(redis, namespace, queue) do 
    Redis.lpop!(redis, queue_key(namespace, queue))
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
    [h | rq]  = Shuffle.shuffle(queues)
    case dequeue(redis, namespace, h) do
      nil -> dequeue_random(redis, namespace, rq)
      job -> job
    end
  end

  defp job_json(queue, worker, args) do
    job = HashDict.new([{:queue, queue}, {:class, worker}, {:args, args}])
    JSEX.encode!(job)
  end
end
