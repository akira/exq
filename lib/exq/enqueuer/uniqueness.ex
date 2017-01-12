defmodule Exq.Enqueuer.Uniqueness do
  import Base, only: [encode16: 1]
  import String, only: [downcase: 1]
  alias Exq.Redis.Connection, as: Redis
  alias Exp.Middleware.Pipeline

  # def with_unique_lock(callback, state, queue \\ "default", worker \\ "", args \\ []) do
  #   with_unique_lock(callback, state, queue, worker, args, nil)
  # end

  def with_unique_lock(callback, state, queue \\ "default", worker \\ "", args \\ [], uniquekey \\ nil) do
    redis = state.redis
    simple_key = uniquekey || Enum.join(args, ",")
    enqueue_key = combined_key(state.namespace, queue, Atom.to_string(worker), simple_key)

    if unique_key_exists?(redis, enqueue_key) do
      {:job_not_unique, enqueue_key}
    else
      set_key(redis, enqueue_key)
      {:reply, response, _pipeline} = callback.()
      {:ok, job_id} = response
      completion_key = generate_completion_key(state.namespace, job_id)
      Redis.set!(state.redis, completion_key, enqueue_key)
      {:ok, response}
    end
  end

  def remove_key(redis, key), do: Redis.del!(redis, key)
  def hash_string(key), do: :crypto.hash(:md5, key) |> encode16 |> downcase
  def generate_completion_key(namespace, job_id), do: "#{namespace}:uniqueness-clear-when-complete:#{job_id}"

  def remove_locks(pipeline) do
    job_id = pipeline.assigns[:job].jid
    namespace = pipeline.assigns[:namespace]
    redis = pipeline.assigns[:redis]

    completion_key = generate_completion_key(namespace, job_id)
    enqueue_key = Redis.get!(redis, completion_key)
    remove_key(redis, enqueue_key)
    remove_key(redis, completion_key)

    pipeline
  end

  def combined_key(pipeline, key \\ nil) do
    assigns = pipeline.assigns

    ensured_key = case key do
      key when is_binary key -> key
      _ -> Enum.join(assigns[:job].args, ",")
    end

    combined_key(
      assigns[:namespace], assigns[:queue], Atom.to_string(assigns[:worker_module]), ensured_key
    )
  end

  # private

  defp unique_key_exists?(redis, key) do
    case Redis.get!(redis, key) do
      nil -> false
      _ -> true
    end
  end

  defp combined_key(namespace, queue, worker, key) do
    "#{namespace}:#{queue}:#{worker}:uniqueness:#{hash_string key}"
  end

  defp set_key(redis, key), do: Redis.set!(redis, key, "LOCK")
  defp extended_namespace(root_namespace), do: "#{root_namespace}:uniqueness"
end
