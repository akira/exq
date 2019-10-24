defmodule Exq.Redis.Heartbeat do
  require Logger
  alias Exq.Redis.Connection

  def register(redis, namespace, node_id) do
    score = DateTime.to_unix(DateTime.utc_now(), :milliseconds) / 1000

    case Connection.qp(redis, [
           ["MULTI"],
           ["ZREM", sorted_set_key(namespace), node_id],
           ["ZADD", sorted_set_key(namespace), score, node_id],
           ["EXEC"]
         ]) do
      {:ok, ["OK", "QUEUED", "QUEUED", [_, 1]]} ->
        Logger.debug(fn -> "sent heartbeat for #{node_id}" end)
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

  def orphaned_nodes(redis, namespace, interval, missed_heartbeats_allowed) do
    score = DateTime.to_unix(DateTime.utc_now(), :milliseconds) / 1000
    cutoff = score - interval / 1000 * (missed_heartbeats_allowed + 1)
    cutoff = Enum.max([0, cutoff])

    Connection.zrangebyscore(redis, sorted_set_key(namespace), 0, cutoff)
  end

  defp sorted_set_key(namespace) do
    "#{namespace}:heartbeats"
  end
end
