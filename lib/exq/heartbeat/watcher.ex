defmodule Exq.Heartbeat.Watcher do
  use GenServer
  require Logger
  alias Exq.Support.Config

  defmodule State do
    defstruct [:namespace, :redis, :interval, :queues, :node_id, :missed_heartbeats_allowed]
  end

  def start_link(options) do
    GenServer.start_link(
      __MODULE__,
      %State{
        namespace: Keyword.fetch!(options, :namespace),
        redis: Keyword.fetch!(options, :redis),
        interval: Keyword.fetch!(options, :heartbeat_interval),
        node_id: Keyword.get(options, :node_id, Config.node_identifier().node_id()),
        queues: Keyword.fetch!(options, :queues),
        missed_heartbeats_allowed: Keyword.fetch!(options, :missed_heartbeats_allowed)
      },
      []
    )
  end

  def init(state) do
    :ok = schedule_verify(state.interval)
    {:ok, state}
  end

  def handle_info(:verify, state) do
    sorted_set_key = "#{state.namespace}:heartbeats"

    score = DateTime.utc_now() |> DateTime.to_unix(:second)
    cutoff = score - state.interval / 1000 * (state.missed_heartbeats_allowed + 1)
    cutoff = Enum.max([0, cutoff])

    case Redix.command(state.redis, ["ZRANGEBYSCORE", sorted_set_key, 0, cutoff]) do
      {:ok, node_ids} ->
        Enum.each(node_ids, fn node_id ->
          :ok = re_enqueue_backup(state, node_id)
        end)

      error ->
        Logger.error("Failed to fetch heartbeats. Unexpected error from redis: #{inspect(error)}")
    end

    :ok = schedule_verify(state.interval)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error("Received unexpected info message in #{__MODULE__} #{inspect(msg)}")
    {:noreply, state}
  end

  defp schedule_verify(interval) do
    _reference = Process.send_after(self(), :verify, interval)
    :ok
  end

  defp re_enqueue_backup(state, node_id) do
    Logger.info(
      "#{node_id} missed the last #{state.missed_heartbeats_allowed} heartbeats. Re-enqueing jobs from backup."
    )

    case Redix.command(state.redis, ["SMEMBERS", "#{state.namespace}:queues"]) do
      {:ok, queues} ->
        Enum.uniq(queues ++ state.queues)
        |> Enum.each(fn queue ->
          Exq.Redis.JobQueue.re_enqueue_backup(state.redis, state.namespace, node_id, queue)
        end)

        sorted_set_key = "#{state.namespace}:heartbeats"

        case Redix.command(state.redis, ["ZREM", sorted_set_key, node_id]) do
          {:ok, _} ->
            :ok

          error ->
            Logger.error(
              "Failed to clear old heartbeat. Unexpected error from redis: #{inspect(error)}"
            )
        end

      error ->
        Logger.error("Failed to fetch queues. Unexpected error from redis: #{inspect(error)}")
    end

    :ok
  end
end
