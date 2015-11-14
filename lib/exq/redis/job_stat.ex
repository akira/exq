defmodule Exq.Redis.JobStat do
  require Logger
  use Timex

  alias Exq.Support.Binary
  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue
  alias Exq.Support.Json
  alias Exq.Support.Job
  alias Exq.Stats.Process

  def record_processed(redis, namespace, _job) do
    time = DateFormat.format!(Date.universal, "%Y-%m-%d %T %z", :strftime)
    date = DateFormat.format!(Date.universal, "%Y-%m-%d", :strftime)

    [{:ok, count}, {:ok, _,}, {:ok, _}, {:ok, _}] = Connection.qp(redis,[
      ["INCR", JobQueue.full_key(namespace, "stat:processed")],
      ["INCR", JobQueue.full_key(namespace, "stat:processed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:processed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:processed:#{date}")]
    ])
    {:ok, count}
  end

  def record_failure(redis, namespace, error, _job) do
    time = DateFormat.format!(Date.universal, "%Y-%m-%d %T %z", :strftime)
    date = DateFormat.format!(Date.universal, "%Y-%m-%d", :strftime)

    [{:ok, count}, {:ok, _,}, {:ok, _}, {:ok, _}] = Connection.qp(redis, [
      ["INCR", JobQueue.full_key(namespace, "stat:failed")],
      ["INCR", JobQueue.full_key(namespace, "stat:failed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:failed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:failed:#{date}")]
    ])
    {:ok, count}
  end

  def busy(redis, namespace) do
    Connection.scard!(redis, JobQueue.full_key(namespace, "processes"))
  end

  def processes(redis, namespace) do
    Connection.smembers!(redis, JobQueue.full_key(namespace, "processes"))
  end

  def add_process(redis, namespace, process) do
    pid = to_string(:io_lib.format("~p", [process.pid]))

    process = Enum.into([{:pid, pid}, {:host, process.host}, {:job, process.job}, {:started_at, process.started_at}], HashDict.new)
    json = Json.encode!(process)

    Connection.sadd!(redis, JobQueue.full_key(namespace, "processes"), json)
    :ok
  end

  def remove_process(redis, namespace, hostname, pid) do
    pid = to_string(:io_lib.format("~p", [pid]))

    processes = Connection.smembers!(redis, JobQueue.full_key(namespace, "processes"))

    finder = fn(p) ->
      case Json.decode(p) do
        { :ok, proc } -> (Dict.get(proc, "pid") == pid) && (Dict.get(proc, "host") == hostname)
        { :error, _ } -> false
      end
    end

    proc = Enum.find(processes, finder)

    case proc do
      nil ->
        {:not_found, nil}
      p ->
        Connection.srem!(redis, JobQueue.full_key(namespace, "processes"), proc)
        {:ok, p}
    end

  end

  def find_failed(redis, namespace, jid) do
    Connection.lrange!(redis, JobQueue.full_key(namespace, "failed"), 0, -1)
      |> JobQueue.find_job(jid)
  end

  def remove_queue(redis, namespace, queue) do
    Connection.srem!(redis, JobQueue.full_key(namespace, "queues"), queue)
    Connection.del!(redis, JobQueue.queue_key(namespace, queue))
  end

  def remove_failed(redis, namespace, jid) do
    Connection.decr!(redis, JobQueue.full_key(namespace, "stat:failed"))
    {:ok, failure, _idx} = find_failed(redis, namespace, jid)
    Connection.lrem!(redis, JobQueue.full_key(namespace, "failed"), failure)
  end

  def clear_failed(redis, namespace) do
    Connection.set!(redis, JobQueue.full_key(namespace, "stat:failed"), 0)
    Connection.del!(redis, JobQueue.full_key(namespace, "failed"))
  end

  def clear_processes(redis, namespace) do
    Connection.del!(redis, JobQueue.full_key(namespace, "processes"))
  end

  def realtime_stats(redis, namespace) do
    failure_keys = Connection.keys!(redis, JobQueue.full_key(namespace, "stat:failed_rt:*"))
    failures = for key <- failure_keys do
      date = Binary.take_prefix(key, JobQueue.full_key(namespace, "stat:failed_rt:"))
      count = Connection.get!(redis, key)
      {date, count}
    end

    success_keys = Connection.keys!(redis, JobQueue.full_key(namespace, "stat:processed_rt:*"))
    successes = for key <- success_keys do
      date = Binary.take_prefix(key, JobQueue.full_key(namespace, "stat:processed_rt:"))
      count = Connection.get!(redis, key)
      {date, count}
    end

    {:ok, failures, successes}
  end

end