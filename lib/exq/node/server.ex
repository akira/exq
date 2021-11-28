defmodule Exq.Node.Server do
  use GenServer
  require Logger
  alias Exq.Support.Config
  alias Exq.Support.Time
  alias Exq.Redis.JobStat
  alias Exq.Support.Node

  defmodule State do
    defstruct [
      :node,
      :interval,
      :namespace,
      :redis,
      :node_id,
      :manager,
      :workers_sup,
      ping_count: 0
    ]
  end

  def start_link(options) do
    node_id = Keyword.get(options, :node_id, Config.node_identifier().node_id())

    GenServer.start_link(
      __MODULE__,
      %State{
        manager: Keyword.fetch!(options, :manager),
        workers_sup: Keyword.fetch!(options, :workers_sup),
        node_id: node_id,
        node: build_node(node_id),
        namespace: Keyword.fetch!(options, :namespace),
        redis: Keyword.fetch!(options, :redis),
        interval: 5000
      },
      []
    )
  end

  def init(state) do
    :ok = schedule_ping(state.interval)
    {:ok, state}
  end

  def handle_info(
        :ping,
        %{
          node: node,
          namespace: namespace,
          redis: redis,
          manager: manager,
          workers_sup: workers_sup
        } = state
      ) do
    {:ok, queues} = Exq.subscriptions(manager)
    busy = Exq.Worker.Supervisor.workers_count(workers_sup)
    node = %{node | queues: queues, busy: busy, quiet: Enum.empty?(queues)}

    :ok =
      JobStat.node_ping(redis, namespace, node)
      |> process_signal(state)

    if Integer.mod(state.ping_count, 10) == 0 do
      JobStat.prune_dead_nodes(redis, namespace)
    end

    :ok = schedule_ping(state.interval)
    {:noreply, %{state | ping_count: state.ping_count + 1}}
  end

  def handle_info(msg, state) do
    Logger.error("Received unexpected info message in #{__MODULE__} #{inspect(msg)}")
    {:noreply, state}
  end

  defp process_signal(nil, _), do: :ok

  defp process_signal("TSTP", state) do
    Logger.info("Received TSTP, unsubscribing from all queues")
    :ok = Exq.unsubscribe_all(state.manager)
  end

  defp process_signal(unknown, _) do
    Logger.warn("Received unsupported signal #{unknown}")
    :ok
  end

  defp schedule_ping(interval) do
    _reference = Process.send_after(self(), :ping, interval)
    :ok
  end

  defp build_node(node_id) do
    {:ok, hostname} = :inet.gethostname()

    %Node{
      hostname: to_string(hostname),
      started_at: Time.unix_seconds(),
      pid: List.to_string(:os.getpid()),
      identity: node_id
    }
  end
end
