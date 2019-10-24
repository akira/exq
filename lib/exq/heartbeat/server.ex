defmodule Exq.Heartbeat.Server do
  use GenServer
  require Logger
  alias Exq.Support.Config

  defmodule State do
    defstruct [:namespace, :node_id, :redis, :interval]
  end

  def start_link(options) do
    GenServer.start_link(
      __MODULE__,
      %State{
        namespace: Keyword.fetch!(options, :namespace),
        node_id: Keyword.get(options, :node_id, Config.node_identifier().node_id()),
        redis: Keyword.fetch!(options, :redis),
        interval: Keyword.fetch!(options, :heartbeat_interval)
      },
      []
    )
  end

  def init(state) do
    :ok = schedule_ping(0)
    {:ok, state}
  end

  def handle_info(:ping, state) do
    sorted_set_key = "#{state.namespace}:heartbeats"
    score = DateTime.utc_now() |> DateTime.to_unix(:second)

    case Redix.pipeline(state.redis, [
           ["MULTI"],
           ["ZREM", sorted_set_key, state.node_id],
           ["ZADD", sorted_set_key, score, state.node_id],
           ["EXEC"]
         ]) do
      {:ok, ["OK", "QUEUED", "QUEUED", [_, 1]]} ->
        Logger.debug(fn -> "sent heartbeat for #{state.node_id}" end)
        :ok = schedule_ping(state.interval)

      error ->
        Logger.error("Failed to send heartbeat. Unexpected error from redis: #{inspect(error)}")
        :ok = schedule_ping(Enum.min([state.interval, 5000]))
    end

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.error("Received unexpected info message in #{__MODULE__} #{inspect(msg)}")
    {:noreply, state}
  end

  defp schedule_ping(interval) do
    _reference = Process.send_after(self(), :ping, interval)
    :ok
  end
end
