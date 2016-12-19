defmodule Exq.Enqueuer.Uniqueness do
  import Base, only: [encode16: 1]
  import String, only: [downcase: 1]
  alias Exq.Redis.Connection, as: Redis
  alias Exp.Middleware.Pipeline

  def with_unique_lock(callback, state, queue \\ "default", worker \\ "", args \\ []) do
    redis = state.redis
    args_key = Enum.join(args, ",")
    key = combined_key(state.namespace, queue, Atom.to_string(worker), args_key)

    if unique_key_exists?(redis, key) do
      {:job_not_unique, key}
    else
      set_key(redis, key)
      response = callback.()
      {:ok, response}
    end
  end

  def remove_key(redis, key), do: Redis.del!(redis, key)
  def hash_string(key), do: :crypto.hash(:md5, key) |> encode16 |> downcase

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
