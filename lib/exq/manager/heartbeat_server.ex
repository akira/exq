defmodule HeartbeatServer do
  use GenServer
  alias Exq.Redis.JobQueue
  alias Exq.Redis.Connection
  alias Exq.Support.Time

  def start_link(master_state) do
    GenServer.start_link(__MODULE__, master_state)
  end

  def init(master_state) do
    worker_init = [ ["DEL", "#{redis_worker_name(master_state)}:workers"] ]
      ++ getRedisCommands(master_state)
    Connection.qp!(master_state.redis, worker_init)

    schedule_work()

    {:ok, master_state}
  end

  def handle_info(:heartbeat, master_state) do
    schedule_work()

    current_state = GenServer.call(Map.get(master_state, :pid), :get_state)
    Connection.qp!(current_state.redis, getRedisCommands(current_state))

    {:noreply, current_state}
  end

  defp schedule_work() do
    Process.send_after(self(), :heartbeat, 1000)
  end

  defp redis_worker_name(state) do
    JobQueue.full_key(state.namespace, "#{state.node_id}:elixir")
  end

  defp getRedisCommands(state) do
    name = redis_worker_name(state)
    [
      ["SADD", JobQueue.full_key(state.namespace, "processes"), name],
      ["HSET", name, "quiet", "false"],
      ["HSET", name, "info", Poison.encode!(%{ hostname: state.node_id, started_at: state.started_at, pid: "#{:erlang.pid_to_list(state.pid)}", concurrency: cocurency_count(state), queues: state.queues})],
      ["HSET", name, "beat", Time.unix_seconds],
      ["EXPIRE", name, (state.poll_timeout / 1000 + 5)], # expire information about live worker in poll_interval + 5s
    ]
  end


  defp cocurency_count(state) do
    Enum.map(state.queues, fn(q) ->
      [{_, concurrency, _}] = :ets.lookup(state.work_table, q)
      cond do
        concurrency == :infinite -> 1000000
        true -> concurrency
      end
    end)
    |> Enum.sum
  end

end
