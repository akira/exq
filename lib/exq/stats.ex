
defmodule Exq.Stats do
  use GenServer
  use Timex
  require Logger

  defmodule State do
    defstruct redis: nil
  end

##===========================================================
## gen server callbacks
##===========================================================

  def start_link(redis) do
    GenServer.start_link(__MODULE__, {redis}, [])
  end

  # These are the callbacks that GenServer.Behaviour will use
  def init({redis}) do
    {:ok, %State{redis: redis}}
  end

  def handle_cast({:record_processed, namespace, job}, state) do
    record_processed(state.redis, namespace, job)
    {:noreply, state}
  end

  def handle_cast({:record_failure, namespace, error, job}, state) do
    record_failure(state.redis, namespace, error, job)
    {:noreply, state}
  end

  def handle_cast(data, state) do
    Logger.error("INVALID MESSAGE #{data}")
    {:noreply, state}
  end

  def handle_call({:stop}, _from, state) do
    { :stop, :normal, :ok, state }
  end

  def handle_info(info, state) do
    Logger.error("INVALID MESSAGE #{info}")
    {:noreply, state}
  end

  def terminate(_reason, _state) do
    {:ok}
  end

  def code_change(_old_version, state, _extra) do
    {:ok, state}
  end

##===========================================================
## Methods
##===========================================================

  def record_processed(redis, namespace, job) do
    count = Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:processed"))
    date = DateFormat.format!(Date.local, "%Y-%m-%d", :strftime)
    Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:processed:#{date}"))
    {:ok, count}
  end

  def record_failure(redis, namespace, error, job) do
    count = Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:failed"))
    date = DateFormat.format!(Date.local, "%Y-%m-%d", :strftime)
    Exq.Redis.incr!(redis, Exq.RedisQueue.full_key(namespace, "stat:failed:#{date}"))

    failed_at = DateFormat.format!(Date.local, "{ISO}")

    job = Poison.decode!(job, as: Exq.Job)
    job = %{job | failed_at: failed_at, error_class: "ExqGenericError", error_message: error}
    job_json = Poison.encode!(job, %{})

    Exq.Redis.rpush!(redis, Exq.RedisQueue.full_key(namespace, "failed"), job_json)

    {:ok, count}
  end

  def find_failed(redis, namespace, jid) do
    errors = Exq.Redis.lrange!(redis, Exq.RedisQueue.full_key(namespace, "failed"))

    finder = fn({j, idx}) ->
      job = Poison.decode!(j, as: Exq.Job)
      job.jid == jid
    end

    error = Enum.find(Enum.with_index(errors), finder)

    case error do
      nil ->
        {:not_found, nil}
      _ ->
        {job, idx} = error
        {:ok, job, idx}
    end
  end
end
