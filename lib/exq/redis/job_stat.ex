defmodule Exq.Redis.JobStat do
  require Logger
  use Timex

  alias Exq.Support.Binary
  alias Exq.Redis.Connection
  alias Exq.Redis.JobQueue

  def record_processed(redis, namespace, _job) do
    time = DateFormat.format!(Date.universal, "%Y-%m-%d %T %z", :strftime)
    date = DateFormat.format!(Date.universal, "%Y-%m-%d", :strftime)

    {:ok, [count, _, _, _]} = Connection.qp(redis,[
      ["INCR", JobQueue.full_key(namespace, "stat:processed")],
      ["INCR", JobQueue.full_key(namespace, "stat:processed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:processed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:processed:#{date}")]
    ])
    {:ok, count}
  end

  def record_failure(redis, namespace, _error, _job) do
    time = DateFormat.format!(Date.universal, "%Y-%m-%d %T %z", :strftime)
    date = DateFormat.format!(Date.universal, "%Y-%m-%d", :strftime)

    {:ok, [count, _, _, _]} = Connection.qp(redis, [
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

  def add_process(redis, namespace, process_info) do
    json = Exq.Support.Process.to_json(process_info)
    Connection.sadd!(redis, JobQueue.full_key(namespace, "processes"), json)
    :ok
  end

  def remove_process(redis, namespace, process_info) do
    json = Exq.Support.Process.to_json(process_info)
    Connection.srem!(redis, JobQueue.full_key(namespace, "processes"), json)
    :ok
  end

  def find_failed(redis, namespace, jid) do
    Connection.zrange!(redis, JobQueue.full_key(namespace, "dead"), 0, -1)
      |> JobQueue.find_job(jid)
  end

  def remove_queue(redis, namespace, queue) do
    Connection.srem!(redis, JobQueue.full_key(namespace, "queues"), queue)
    Connection.del!(redis, JobQueue.queue_key(namespace, queue))
  end

  def remove_failed(redis, namespace, jid) do
    Connection.decr!(redis, JobQueue.full_key(namespace, "stat:failed"))
    {:ok, failure, _idx} = find_failed(redis, namespace, jid)
    Connection.zrem!(redis, JobQueue.full_key(namespace, "dead"), failure)
  end

  def clear_failed(redis, namespace) do
    Connection.set!(redis, JobQueue.full_key(namespace, "stat:failed"), 0)
    Connection.del!(redis, JobQueue.full_key(namespace, "dead"))
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