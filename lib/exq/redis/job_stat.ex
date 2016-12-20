defmodule Exq.Redis.JobStat do
  @moduledoc """
  The JobStat module encapsulates storing system-wide stats on top of Redis
  It aims to be compatible with the Sidekiq stats format.
  """

  require Logger
  alias Exq.Support.{Binary, Process, Job, Time}
  alias Exq.Redis.{Connection, JobQueue}

  def record_processed(redis, namespace, _job, current_date \\ DateTime.utc_now) do
    {time, date} = Time.format_current_date(current_date)

    {:ok, [count, _, _, _]} = Connection.qp(redis,[
      ["INCR", JobQueue.full_key(namespace, "stat:processed")],
      ["INCR", JobQueue.full_key(namespace, "stat:processed_rt:#{time}")],
      ["EXPIRE", JobQueue.full_key(namespace, "stat:processed_rt:#{time}"), 120],
      ["INCR", JobQueue.full_key(namespace, "stat:processed:#{date}")]
    ])
    {:ok, count}
  end

  def record_failure(redis, namespace, _error, _job, current_date \\ DateTime.utc_now) do
    {time, date} = Time.format_current_date(current_date)

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
    list = Connection.smembers!(redis, JobQueue.full_key(namespace, "processes")) || []
    Enum.map(list, &Process.decode/1)
  end

  def add_process(redis, namespace, process_info) do
    serialized = Exq.Support.Process.encode(process_info)
    Connection.sadd!(redis, JobQueue.full_key(namespace, "processes"), serialized)
    :ok
  end

  def remove_process(redis, namespace, process_info) do
    serialized = Exq.Support.Process.encode(process_info)
    Connection.srem!(redis, JobQueue.full_key(namespace, "processes"), serialized)
    :ok
  end

  def find_failed(redis, namespace, jid) do
    redis
    |> Connection.zrange!(JobQueue.full_key(namespace, "dead"), 0, -1)
    |> JobQueue.search_jobs(jid)
  end

  def remove_queue(redis, namespace, queue) do
    Connection.qp(redis, [
      ["SREM", JobQueue.full_key(namespace, "queues"), queue],
      ["DEL", JobQueue.queue_key(namespace, queue)]
    ])
  end

  def remove_failed(redis, namespace, jid) do
    {:ok, failure} = find_failed(redis, namespace, jid)
    Connection.qp(redis, [
      ["DECR", JobQueue.full_key(namespace, "stat:failed")],
      ["ZREM", JobQueue.full_key(namespace, "dead"), Job.encode(failure)]
    ])
  end

  def clear_failed(redis, namespace) do
    Connection.qp(redis, [
      ["SET", JobQueue.full_key(namespace, "stat:failed"), 0],
      ["DEL", JobQueue.full_key(namespace, "dead")]
    ])
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
      if Enum.empty?(keys) do
        []
      else
        {:ok, counts} = Connection.qp(redis, Enum.map(keys, &(["GET", &1])))
        Enum.map(keys, &(Binary.take_prefix(&1, JobQueue.full_key(namespace, ns))))
        |> Enum.zip(counts)
      end
    end
  end

  def get_count(redis, namespace, key) do
    case Connection.get!(redis, JobQueue.full_key(namespace, "stat:#{key}")) do
      :undefined ->
        0
      nil ->
        0
      count when is_integer(count) ->
        count
      count ->
        {val, _} = Integer.parse(count)
        val
    end
  end
end
