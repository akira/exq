defmodule Exq.Heartbeat.Monitor do
  use GenServer
  require Logger
  alias Exq.Redis.Heartbeat
  alias Exq.Support.Config

  defmodule State do
    defstruct [
      :namespace,
      :redis,
      :interval,
      :queues,
      :node_id,
      :missed_heartbeats_allowed,
      :stats
    ]
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
        stats: Keyword.get(options, :stats),
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
    case Heartbeat.orphaned_nodes(
           state.redis,
           state.namespace,
           state.interval,
           state.missed_heartbeats_allowed
         ) do
      {:ok, node_ids} ->
        Enum.each(node_ids, fn {node_id, score} ->
          :ok = re_enqueue_backup(state, node_id, score)
        end)

      _error ->
        :ok
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

  defp re_enqueue_backup(state, node_id, score) do
    Logger.info(
      "#{node_id} missed the last #{state.missed_heartbeats_allowed} heartbeats. Re-enqueing jobs from backup and cleaning up stats."
    )

    Enum.uniq(Exq.Redis.JobQueue.list_queues(state.redis, state.namespace) ++ state.queues)
    |> Enum.each(fn queue ->
      Heartbeat.re_enqueue_backup(state.redis, state.namespace, node_id, queue, score)
    end)

    if state.stats do
      :ok = Exq.Stats.Server.cleanup_host_stats(state.stats, state.namespace, node_id)
    end

    _ = Heartbeat.unregister(state.redis, state.namespace, node_id)
    :ok
  end
end
