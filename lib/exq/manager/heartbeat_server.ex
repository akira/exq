defmodule Exq.Heartbeat.Server do
  use GenServer
  alias Exq.Redis.Connection
  alias Exq.Redis.JobStat

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(opts) do
    schedule_new_work(Exq.Manager.Server.server_name(opts[:name]))
    {:ok}
  end

  def heartbeat(name, status) do
    master_state = GenServer.call(name, :get_state)
    init_data = if status, do: [["DEL", "#{master_state.name}:workers"]], else: []
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
  end

  defp schedule_new_work(name, status \\ false) do
   :timer.sleep(1000)
   heartbeat(name, status)
   schedule_new_work(name)
  end
end
