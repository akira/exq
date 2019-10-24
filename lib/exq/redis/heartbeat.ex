defmodule Exq.Redis.Heartbeat do
  require Logger
  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue
  alias Exq.Redis.Script

  def register(redis, namespace, node_id) do
    score = DateTime.to_unix(DateTime.utc_now(), :milliseconds) / 1000

    case Connection.qp(redis, [
           ["MULTI"],
           ["ZREM", sorted_set_key(namespace), node_id],
           ["ZADD", sorted_set_key(namespace), score, node_id],
           ["EXEC"]
         ]) do
      {:ok, ["OK", "QUEUED", "QUEUED", [_, 1]]} ->
        :ok

      error ->
        Logger.error("Failed to send heartbeat. Unexpected error from redis: #{inspect(error)}")
        error
    end
  end

  def unregister(redis, namespace, node_id) do
    case Connection.zrem(redis, sorted_set_key(namespace), node_id) do
      {:ok, _} ->
        :ok

      error ->
        Logger.error(
          "Failed to clear old heartbeat. Unexpected error from redis: #{inspect(error)}"
        )

        error
    end
  end

  def re_enqueue_backup(redis, namespace, node_id, queue, current_score) do
    resp =
      Script.eval!(
        redis,
        :heartbeat_re_enqueue_backup,
        [
          JobQueue.backup_queue_key(namespace, node_id, queue),
          JobQueue.queue_key(namespace, queue),
          sorted_set_key(namespace)
        ],
        [node_id, current_score]
      )

    case resp do
      {:ok, job} ->
        if String.valid?(job) do
          Logger.info(
            "Re-enqueueing job from backup for node_id [#{node_id}] and queue [#{queue}]"
          )

          re_enqueue_backup(redis, namespace, node_id, queue, current_score)
        end

      _ ->
        nil
    end
  end

  def orphaned_nodes(redis, namespace, interval, missed_heartbeats_allowed) do
    score = DateTime.to_unix(DateTime.utc_now(), :milliseconds) / 1000
    cutoff = score - interval / 1000 * (missed_heartbeats_allowed + 1)
    cutoff = Enum.max([0, cutoff])

    with {:ok, results} <-
           Connection.zrangebyscorewithscore(redis, sorted_set_key(namespace), 0, cutoff) do
      {:ok,
       Enum.chunk_every(results, 2)
       |> Map.new(fn [k, v] -> {k, v} end)}
    end
  end

  defp sorted_set_key(namespace) do
    "#{namespace}:heartbeats"
  end
end
