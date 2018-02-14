defmodule Exq.Heartbeat.Server do
  use GenServer
  alias Exq.Redis.JobQueue
  alias Exq.Redis.Connection
  alias Exq.Support.Config
  alias Exq.Support.Time
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
    schedule_work(state)
    {:ok, state}
  end

  def handle_cast({:heartbeat, master_state}, state) do
    schedule_work(state)
    current_state = struct(State, Map.from_struct(master_state))
    Connection.qp!(
      current_state.redis,
      JobStat.get_redis_commands(
        current_state.namespace,
        current_state.node_id,
        current_state.started_at,
        current_state.pid,
        current_state.queues,
        current_state.work_table,
        current_state.poll_timeout
        )
      )
    {:noreply, current_state}
  end

  defp schedule_work(state) do
    Process.send_after(state.name, {:get_state, self()}, 1000)
  end

  defp redis_worker_name(state) do
    JobQueue.full_key(state.namespace, "#{state.node_id}:elixir")
  end
end
