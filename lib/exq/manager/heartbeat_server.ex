defmodule Exq.Heartbeat.Server do
  use GenServer
  alias Exq.Redis.Connection
  alias Exq.Support.Config
  alias Exq.Redis.JobStat

  defmodule State do
    defstruct name: nil, node_id: nil, namespace: nil, started_at: nil, pid: nil, queues: nil, poll_timeout: nil, work_table: nil, redis: nil
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    state = %State{
      name: Exq.Manager.Server.server_name(opts[:name]),
      redis: opts[:redis],
      node_id:  Config.node_identifier.node_id(),
      namespace: opts[:namespace],
      queues: opts[:queues],
      poll_timeout: opts[:poll_timeout]
    }
    schedule_work(state, true, 0)
    {:ok, state}
  end

  def handle_cast({:heartbeat, master_state, status}, state) do
    schedule_work(state)
    master_data = Map.from_struct(master_state)
    current_state = %{struct(State, master_data) | name: state.name}
    init_data = if status, do: [["DEL", "#{current_state.name}:workers"]], else: []
    data = init_data ++ JobStat.get_redis_commands(
      current_state.namespace,
      current_state.node_id,
      current_state.started_at,
      current_state.pid,
      current_state.queues,
      current_state.work_table,
      current_state.poll_timeout
    )
    Connection.qp!(
      current_state.redis,
      data
    )
    {:noreply, current_state}
  end

  defp schedule_work(state, status \\ false, timeout \\ 1000) do
    Process.send_after(state.name, {:get_state, self(), status}, 1000)
  end
end
