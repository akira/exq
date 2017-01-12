defmodule Exq.Enqueuer.Uniqueness do
  @moduledoc """
    This module is used to enforce job uniqueness when a job is first enqueued.
    It does this by either receiving or generating a key and saving it in redis, (the "enqueue key").
    Finally it saves a reference to this key referenced by the job number, (the "completion key").
    From the middleware, we remove both keys when the job completes via the remove_locks/1 function.
  """

  import Base, only: [encode16: 1]
  import String, only: [downcase: 1]
  alias Exq.Redis.Connection, as: Redis
  alias Exp.Middleware.Pipeline

  def remove_key(redis, key), do: Redis.del!(redis, key)
  def hash_string(key), do: :crypto.hash(:md5, key) |> encode16 |> downcase

  def with_unique_lock(callback, redis, namespace, args \\ [], key \\ "") do
    enqueue_key = generate_enqueue_key(namespace, key)

    if enqueue_key_exists?(redis, enqueue_key) do
      {:job_not_unique, enqueue_key}
    else
      set_key(redis, enqueue_key)
      {:reply, {:ok, jid}, _pipeline} = callback.()
      completion_key = generate_completion_key(namespace, jid)
      set_key(redis, completion_key, enqueue_key)
      {:ok, jid}
    end
  end

  def remove_locks(pipeline) do
    %{
      namespace: namespace, queue: queue, worker_module: worker, job: job, redis: redis
    } = pipeline.assigns

    uniqueness_namespace = combined_namespace(namespace, queue, worker)
    completion_key = generate_completion_key(uniqueness_namespace, job.jid)
    enqueue_key = Redis.get!(redis, completion_key)

    remove_key(redis, enqueue_key)
    remove_key(redis, completion_key)

    pipeline
  end

  def combined_namespace(namespace, queue, worker) do
    "#{namespace}:#{queue}:#{Atom.to_string worker}"
  end

  defp generate_enqueue_key(namespace, key) do
    "#{namespace}:enqueue-lock:#{hash_string key}"
  end

  defp generate_completion_key(namespace, job_id) do
    "#{namespace}:unlock-when-complete:#{job_id}"
  end

  defp enqueue_key_exists?(redis, key) do
    case Redis.get!(redis, key) do
      nil -> false
      _ -> true
    end
  end

  # Set a key in redis, value with the value defaulting to LOCK
  defp set_key(redis, key, value \\ "LOCK"), do: Redis.set!(redis, key, value)
end
