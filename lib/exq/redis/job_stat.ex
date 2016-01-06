defmodule Exq.Redis.JobStat do
  @moduledoc """
  The JobStat module encapsulates storing system-wide stats on top of Redis
  It aims to be compatible with the Sidekiq stats format.
  """

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
    {:ok, [failure_keys, success_keys]} = Connection.qp(redis, [
      ["KEYS", JobQueue.full_key(namespace, "stat:failed_rt:*")],
      ["KEYS", JobQueue.full_key(namespace, "stat:processed_rt:*")]
    ])

    formatter = realtime_stats_formatter(redis, namespace)
    failures = formatter.(failure_keys, "stat:failed_rt:")
    successes = formatter.(success_keys, "stat:processed_rt:")

    {:ok, failures, successes}
  end

  defp realtime_stats_formatter(redis, namespace) do
    fn(keys, ns) ->
      {:ok, counts } = Connection.qp(redis, Enum.map(keys, &(["GET", &1])))
      Enum.map(keys, &(Binary.take_prefix(&1, JobQueue.full_key(namespace, ns))))
      |> Enum.zip(counts)
    end
  end
end
