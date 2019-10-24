defmodule Exq.Heartbeat.Server do
  use GenServer
  require Logger
  alias Exq.Support.Config
  alias Exq.Redis.Heartbeat

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
    case Heartbeat.register(state.redis, state.namespace, state.node_id) do
      :ok ->
        :ok = schedule_ping(state.interval)

      error ->
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
