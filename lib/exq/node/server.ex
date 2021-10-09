defmodule Exq.Node.Server do
  use GenServer
  require Logger
  alias Exq.Support.Config
  alias Exq.Support.Time
  alias Exq.Redis.JobStat

  defmodule State do
    defstruct [:info, :interval, :namespace, :redis, :node_id, :manager, :workers_sup]
  end

  def start_link(options) do
    node_id = Keyword.get(options, :node_id, Config.node_identifier().node_id())

    GenServer.start_link(
      __MODULE__,
      %State{
        manager: Keyword.fetch!(options, :manager),
        workers_sup: Keyword.fetch!(options, :workers_sup),
        node_id: node_id,
        info: node_info(node_id),
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
          info: info,
          namespace: namespace,
          node_id: node_id,
          redis: redis,
          manager: manager,
          workers_sup: workers_sup
        } = state
      ) do
    {:ok, queues} = Exq.subscriptions(manager)
    info = %{info | queues: queues}
    busy = Exq.Worker.Supervisor.workers_count(workers_sup)

    :ok =
      JobStat.node_ping(redis, namespace, node_id, info, queues, busy)
      |> process_signal(state)

    :ok = schedule_ping(state.interval)
    {:noreply, state}
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

  defp node_info(node_id) do
    {:ok, hostname} = :inet.gethostname()

    %{
      hostname: to_string(hostname),
      started_at: Time.unix_seconds(),
      pid: System.pid(),
      tag: "",
      concurrency: 0,
      queues: [],
      labels: [],
      identity: node_id
    }
  end
end
