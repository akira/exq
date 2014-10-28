defmodule Exq.RedisQueue do
  use Timex

  @default_queue "default"

  def find_job(redis, namespace, jid, queue) do
    jobs = Exq.Redis.lrange!(redis, queue_key(namespace, queue))

    finder = fn({j, idx}) -> 
      job = Poison.decode!(j, as: Exq.Job)
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
    Exq.Redis.sadd!(redis, full_key(namespace, "queues"), queue)
    {jid, job} = job_json(queue, worker, args)
    Exq.Redis.rpush!(redis, queue_key(namespace, queue), job)
    jid
  end

  def dequeue(redis, namespace, queues) when is_list(queues) do
    dequeue_random(redis, namespace, queues)
  end
  def dequeue(redis, namespace, queue) do
    Exq.Redis.lpop!(redis, queue_key(namespace, queue))
  end

  def full_key(namespace, key) do
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
    job = %Exq.Job{queue: queue, class: worker, args: args, jid: jid}
    {jid, Poison.Encoder.encode(job, %{})}
  end
end
