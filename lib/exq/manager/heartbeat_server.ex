defmodule Exq.Heartbeat.Server do
  use GenServer
  alias Exq.Redis.Connection
  alias Exq.Support.Config
  alias Exq.Redis.JobStat

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    schedule_work(Exq.Manager.Server.server_name(opts[:name]), true)
    {:ok, nil}
  end

  def handle_cast({:heartbeat, master_state, name, status}, _state) do
    schedule_work(master_state.pid)
    init_data = if status, do: [["DEL", "#{name}:workers"]], else: []
    data = init_data ++ JobStat.status_process_commands(
      master_state.namespace,
      master_state.node_id,
      master_state.started_at,
      master_state.pid,
      master_state.queues,
      master_state.work_table,
      master_state.poll_timeout
    )
    Connection.qp!(
      master_state.redis,
      data
    )
    {:noreply, nil}
  end

  defp schedule_work(name, status \\ false) do
    Process.send_after(name, {:get_state, self(), name, status}, 1000)
  end
end
